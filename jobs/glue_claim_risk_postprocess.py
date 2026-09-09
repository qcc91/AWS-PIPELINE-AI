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
claim_schema = StructType([StructField("claim_id", StringType(), False), StructField("row_id", LongType(), False)])
predictions = spark.createDataFrame(
    spark.read.text(args["TRANSFORM_OUTPUT_URI"]).rdd.map(lambda row: row.value.strip().split(",")[0]).zipWithIndex(),
    prediction_schema,
)
claim_ids = spark.createDataFrame(
    spark.read.option("header", "true").csv(args["CLAIM_IDS_URI"]).select("claim_id").rdd.map(lambda row: row.claim_id).zipWithIndex(),
    claim_schema,
)
out = claim_ids.join(predictions, "row_id", "inner").drop("row_id").withColumn("fraud_probability", col("fraud_probability_raw").cast("decimal(6,5)")).drop("fraud_probability_raw")
out = out.withColumn("risk_level", when(col("fraud_probability") >= 0.70, lit("HIGH")).when(col("fraud_probability") >= 0.30, lit("MEDIUM")).otherwise(lit("LOW"))).withColumn("model_version", lit(args["MODEL_VERSION"])).withColumn("prediction_timestamp", current_timestamp()).withColumn("_run_id", lit(args["RUN_ID"]))
out.writeTo(f"glue_catalog.{args['GOLD_DATABASE']}.{args['GOLD_TABLE']}").using("iceberg").createOrReplace()
job.commit()
