"""Glue Spark postprocess: join Batch Transform lines to IDs and write Iceberg."""
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql.functions import current_timestamp, when, col, lit
from pyspark.sql.types import LongType, StringType, StructField, StructType

args = getResolvedOptions(__import__("sys").argv, ["JOB_NAME", "TRANSFORM_OUTPUT_URI", "CLAIM_IDS_URI", "GOLD_DATABASE", "GOLD_TABLE", "MODEL_VERSION", "RUN_ID"])
glue = GlueContext(SparkContext.getOrCreate())
job = Job(glue); job.init(args["JOB_NAME"], args)
spark = glue.spark_session
prediction_schema = StructType([StructField("fraud_probability_raw", StringType(), False), StructField("row_id", LongType(), False)])
claim_schema = StructType([StructField("claim_id", StringType(), False), StructField("as_of_date", StringType(), False), StructField("feature_version", StringType(), False), StructField("dataset_version", StringType(), True), StructField("row_id", LongType(), False)])
predictions = spark.createDataFrame(
    spark.read.text(args["TRANSFORM_OUTPUT_URI"]).rdd.map(lambda row: row.value.strip().split(",")[0]).zipWithIndex(),
    prediction_schema,
)
claim_ids = spark.createDataFrame(
    spark.read.option("header", "true").csv(args["CLAIM_IDS_URI"]).select("claim_id", "as_of_date", "feature_version", "dataset_version").rdd.map(lambda row: (row.claim_id, row.as_of_date, row.feature_version, row.dataset_version)).zipWithIndex().map(lambda row: (row[0][0], row[0][1], row[0][2], row[0][3], row[1])),
    claim_schema,
)
prediction_count = predictions.count()
input_count = claim_ids.count()
unique_claim_count = claim_ids.select("claim_id").distinct().count()
invalid_manifest_count = claim_ids.filter(col("claim_id").isNull() | (col("claim_id") == "") | col("as_of_date").isNull() | col("dataset_version").isNull() | (col("dataset_version") == "")).count()
if input_count != prediction_count:
    raise RuntimeError(f"prediction reconciliation failed: input={input_count}, output={prediction_count}")
if unique_claim_count != input_count:
    raise RuntimeError(f"prediction manifest contains {input_count - unique_claim_count} duplicate claim_id values")
if invalid_manifest_count:
    raise RuntimeError(f"prediction manifest contains {invalid_manifest_count} rows without identity, as_of_date, or dataset_version")
out = claim_ids.join(predictions, "row_id", "inner").drop("row_id").withColumn("high_risk_probability", col("fraud_probability_raw").cast("decimal(6,5)")).drop("fraud_probability_raw")
invalid_probability_count = out.filter(col("high_risk_probability").isNull() | (col("high_risk_probability") < 0) | (col("high_risk_probability") > 1)).count()
if invalid_probability_count:
    raise RuntimeError(f"prediction output contains {invalid_probability_count} invalid probabilities")
out = out.withColumn("as_of_date", col("as_of_date").cast("date")).withColumn("risk_level", when(col("high_risk_probability") >= 0.70, lit("HIGH")).when(col("high_risk_probability") >= 0.30, lit("MEDIUM")).otherwise(lit("LOW"))).withColumn("model_version", lit(args["MODEL_VERSION"])).withColumn("model_run_id", lit(args["RUN_ID"])).withColumn("prediction_timestamp", current_timestamp()).withColumn("_run_id", lit(args["RUN_ID"]))
# A replay of the same model output deterministically replaces the current
# claim-risk snapshot. Validation above prevents duplicate business keys.
out.writeTo(f"glue_catalog.{args['GOLD_DATABASE']}.{args['GOLD_TABLE']}").using("iceberg").createOrReplace()
job.commit()
