"""AWS Glue 5 Spark job for Firehose JSON events to Iceberg layers.

Firehose writes newline-delimited JSON under ``stream/``. V1 keeps the
source envelope in Bronze, selects contract fields into Silver, and creates a
small Gold event summary for Athena. Strong deduplication/quarantine gates are
deferred to V2.
"""

from __future__ import annotations

import sys
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

REQUIRED = ["schema_version", "event_id", "event_type", "event_timestamp", "source", "payload"]


def write_iceberg(frame, database: str, table: str, location: str) -> None:
    frame.writeTo(f"glue_catalog.{database}.{table}").using("iceberg").tableProperty("format-version", "2").tableProperty("location", location).createOrReplace()


def main() -> None:
    from awsglue.utils import getResolvedOptions

    args = getResolvedOptions(sys.argv, ["JOB_NAME", "STREAM_BUCKET", "STREAM_PREFIX", "RUN_ID", "LAKEHOUSE_BUCKET", "BRONZE_DATABASE", "SILVER_DATABASE", "GOLD_DATABASE"])
    warehouse = f"s3://{args['LAKEHOUSE_BUCKET']}/lakehouse/"
    spark = (SparkSession.builder.config("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog").config("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog").config("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO").config("spark.sql.catalog.glue_catalog.warehouse", warehouse).config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions").getOrCreate())
    source_uri = f"s3://{args['STREAM_BUCKET']}/{args['STREAM_PREFIX'].strip('/')}/"
    raw = spark.read.json(source_uri)
    missing = sorted(set(REQUIRED) - set(raw.columns))
    if missing:
        raise ValueError(f"stream event schema is missing required fields: {','.join(missing)}")
    bronze = raw.withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn("_source_system", F.lit("kinesis-firehose")).withColumn("_source_object", F.lit(source_uri)).withColumn("_ingested_at", F.current_timestamp()).withColumn("_schema_version", F.lit(1)).withColumn("_record_hash", F.sha2(F.to_json(F.struct(*raw.columns)), 256))
    write_iceberg(bronze, args["BRONZE_DATABASE"], "stream_event", f"{warehouse}bronze/stream_event/")
    silver = bronze
    for optional_id in ("customer_id", "policy_id", "claim_id", "payment_id", "correlation_id"):
        if optional_id not in silver.columns:
            silver = silver.withColumn(optional_id, F.lit(None).cast("string"))
    silver = (silver.filter(F.col("event_id").isNotNull() & F.col("event_type").isNotNull() & F.col("event_timestamp").isNotNull() & F.col("source").isNotNull()).withColumn("event_timestamp", F.to_timestamp("event_timestamp")).filter(F.col("event_timestamp").isNotNull()).select("schema_version", "event_id", "event_type", "event_timestamp", "source", "customer_id", "policy_id", "claim_id", "payment_id", "correlation_id", "payload", "_run_id", "_source_system", "_source_object", "_ingested_at", "_schema_version", "_record_hash"))
    write_iceberg(silver, args["SILVER_DATABASE"], "stream_event", f"{warehouse}silver/stream_event/")
    gold = silver.withColumn("event_date", F.to_date("event_timestamp")).groupBy("event_date", "event_type", "source").agg(F.count("event_id").alias("event_count")).withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn("_source_system", F.lit("kinesis-firehose")).withColumn("_ingested_at", F.current_timestamp()).withColumn("_effective_at", F.current_timestamp()).withColumn("_schema_version", F.lit(1)).withColumn("_record_hash", F.sha2(F.concat_ws("||", "event_date", "event_type", "source"), 256))
    write_iceberg(gold, args["GOLD_DATABASE"], "event_daily_summary", f"{warehouse}gold/event_daily_summary/")
    spark.stop()


if __name__ == "__main__":
    main()
