"""AWS Glue 5 Spark job for the V1 broker claim happy path.

One invocation reads one immutable landing CSV and refreshes the Bronze,
Silver, and Gold Iceberg tables. Full replay/idempotency and quarantine
workflows are intentionally deferred to V2.
"""

from __future__ import annotations

import sys
from urllib.parse import unquote_plus

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

REQUIRED_COLUMNS = [
    "claim_id",
    "claim_number",
    "policy_id",
    "customer_id",
    "claim_status",
    "incident_date",
    "submitted_at",
    "claim_amount",
    "approved_amount",
    "currency_code",
    "description",
    "updated_at",
]
VALID_STATUSES = ["SUBMITTED", "UNDER_REVIEW", "APPROVED", "REJECTED", "PAID", "CLOSED"]


def _write_iceberg(frame, database: str, table: str, location: str) -> None:
    """Create or replace a named Glue Catalog Iceberg table at a stable path."""

    (
        frame.writeTo(f"glue_catalog.{database}.{table}")
        .using("iceberg")
        .tableProperty("format-version", "2")
        .tableProperty("write.format.default", "parquet")
        .tableProperty("location", location)
        .createOrReplace()
    )


def main() -> None:
    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "LANDING_BUCKET",
            "LANDING_KEY",
            "RUN_ID",
            "LAKEHOUSE_BUCKET",
            "BRONZE_DATABASE",
            "SILVER_DATABASE",
            "GOLD_DATABASE",
        ],
    )
    landing_bucket = args["LANDING_BUCKET"]
    landing_key = unquote_plus(args["LANDING_KEY"])
    run_id = args["RUN_ID"]
    lakehouse_bucket = args["LAKEHOUSE_BUCKET"]
    input_uri = f"s3://{landing_bucket}/{landing_key}"
    warehouse = f"s3://{lakehouse_bucket}/lakehouse/"

    spark = (
        SparkSession.builder.config("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
        .config("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        .config("spark.sql.catalog.glue_catalog.warehouse", warehouse)
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .getOrCreate()
    )

    raw = spark.read.option("header", "true").option("mode", "FAILFAST").csv(input_uri)
    missing = sorted(set(REQUIRED_COLUMNS) - set(raw.columns))
    if missing:
        raise ValueError(f"broker claim schema is missing required columns: {','.join(missing)}")

    ingested_at = F.current_timestamp()
    bronze = raw.select(*REQUIRED_COLUMNS).withColumn("_run_id", F.lit(run_id)).withColumn(
        "_source_system", F.lit("broker_csv")
    ).withColumn("_source_object", F.lit(input_uri)).withColumn("_ingested_at", ingested_at).withColumn(
        "_schema_version", F.lit(1)
    ).withColumn("_record_hash", F.sha2(F.concat_ws("||", *[F.col(column) for column in REQUIRED_COLUMNS]), 256))
    _write_iceberg(bronze, args["BRONZE_DATABASE"], "claim", f"{warehouse}bronze/claim/")

    typed = (
        bronze.withColumn("claim_id", F.trim("claim_id"))
        .withColumn("claim_number", F.trim("claim_number"))
        .withColumn("policy_id", F.trim("policy_id"))
        .withColumn("customer_id", F.trim("customer_id"))
        .withColumn("claim_status", F.upper(F.trim("claim_status")))
        .withColumn("currency_code", F.upper(F.trim("currency_code")))
        .withColumn("incident_date", F.to_date("incident_date"))
        .withColumn("submitted_at", F.to_timestamp("submitted_at"))
        .withColumn("updated_at", F.to_timestamp("updated_at"))
        .withColumn("claim_amount", F.col("claim_amount").cast(DecimalType(18, 2)))
        .withColumn("approved_amount", F.col("approved_amount").cast(DecimalType(18, 2)))
    )
    valid = typed.filter(
        F.col("claim_id").isNotNull()
        & (F.col("claim_id") != "")
        & F.col("claim_number").isNotNull()
        & (F.trim(F.col("claim_number")) != "")
        & F.col("policy_id").isNotNull()
        & (F.trim(F.col("policy_id")) != "")
        & F.col("customer_id").isNotNull()
        & (F.trim(F.col("customer_id")) != "")
        & F.col("claim_status").isin(VALID_STATUSES)
        & F.col("currency_code").isNotNull()
        & (F.length(F.trim(F.col("currency_code"))) == 3)
        & F.col("incident_date").isNotNull()
        & F.col("submitted_at").isNotNull()
        & (F.col("incident_date") <= F.to_date(F.col("submitted_at")))
        & F.col("updated_at").isNotNull()
        & (F.col("updated_at") >= F.col("submitted_at"))
        & F.col("claim_amount").isNotNull()
        & (F.col("claim_amount") >= F.lit(0))
        & (F.col("approved_amount").isNull() | (F.col("approved_amount") >= F.lit(0)))
        & (F.col("approved_amount").isNull() | (F.col("approved_amount") <= F.col("claim_amount")))
    )
    latest = valid.withColumn(
        "_rank", F.row_number().over(Window.partitionBy("claim_id").orderBy(F.col("updated_at").desc(), F.col("_record_hash").desc()))
    ).filter(F.col("_rank") == 1).drop("_rank")
    _write_iceberg(latest, args["SILVER_DATABASE"], "claim", f"{warehouse}silver/claim/")

    fact = latest.drop("description").withColumn("_effective_at", F.current_timestamp())
    _write_iceberg(fact, args["GOLD_DATABASE"], "fact_claim", f"{warehouse}gold/fact_claim/")
    summary = latest.groupBy("incident_date", "claim_status", "currency_code").agg(
        F.count("claim_id").alias("claim_count"),
        F.sum("claim_amount").cast(DecimalType(18, 2)).alias("total_claim_amount"),
        F.sum(F.coalesce(F.col("approved_amount"), F.lit(0).cast(DecimalType(18, 2)))).cast(DecimalType(18, 2)).alias("total_approved_amount"),
    ).withColumn("_run_id", F.lit(run_id)).withColumn("_source_system", F.lit("broker_csv")).withColumn(
        "_ingested_at", ingested_at
    ).withColumn("_effective_at", F.current_timestamp()).withColumn("_schema_version", F.lit(1))
    summary = summary.withColumn(
        "_record_hash", F.sha2(F.concat_ws("||", "incident_date", "claim_status", "currency_code"), 256)
    )
    _write_iceberg(summary, args["GOLD_DATABASE"], "claim_daily_summary", f"{warehouse}gold/claim_daily_summary/")
    spark.stop()


if __name__ == "__main__":
    main()
