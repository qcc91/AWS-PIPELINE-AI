"""Materialize DMS S3 CSV change files into V1 Iceberg CDC tables."""

from __future__ import annotations

import sys
from urllib.parse import unquote_plus

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

TABLES = {
    "customers": "customer_id",
    "products": "product_id",
    "policies": "policy_id",
    "claims": "claim_id",
    "payments": "payment_id",
}


def write_iceberg(frame, database: str, table: str, location: str) -> None:
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
            "CDC_PREFIX",
            "CDC_OBJECT_KEY",
            "RUN_ID",
            "LAKEHOUSE_BUCKET",
            "BRONZE_DATABASE",
            "SILVER_DATABASE",
            "GOLD_DATABASE",
        ],
    )
    warehouse = f"s3://{args['LAKEHOUSE_BUCKET']}/lakehouse/"
    spark = (
        SparkSession.builder.config("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
        .config("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        .config("spark.sql.catalog.glue_catalog.warehouse", warehouse)
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .getOrCreate()
    )
    landing_root = f"s3://{args['LANDING_BUCKET']}/{args['CDC_PREFIX'].strip('/')}/public"
    claims = None
    for table, primary_key in TABLES.items():
        table_path = f"{landing_root}/{table}/"
        try:
            raw = spark.read.option("header", "true").option("inferSchema", "false").csv(table_path)
        except Exception as error:
            if "Path does not exist" in str(error) or "PATH_NOT_FOUND" in str(error):
                continue
            raise
        if not raw.columns or primary_key not in raw.columns:
            continue

        op_column = next((name for name in ["Op", "op", "operation"] if name in raw.columns), None)
        timestamp_column = next((name for name in ["_dms_timestamp", "updated_at"] if name in raw.columns), None)
        op = F.upper(F.coalesce(F.col(op_column), F.lit("I"))) if op_column else F.lit("I")
        event_time = F.to_timestamp(F.col(timestamp_column)) if timestamp_column else F.current_timestamp()
        bronze = raw.withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn(
            "_source_system", F.lit("insurance_oltp_dms")
        ).withColumn("_source_object", F.lit(table_path)).withColumn("_ingested_at", F.current_timestamp()).withColumn(
            "_record_hash", F.sha2(F.concat_ws("||", *[F.col(name) for name in raw.columns]), 256)
        ).withColumn("_schema_version", F.lit(1)).withColumn("_operation", op).withColumn("_source_order", event_time)
        write_iceberg(bronze, args["BRONZE_DATABASE"], f"{table}_cdc", f"{warehouse}bronze/{table}_cdc/")

        current = bronze.withColumn("_rank", F.row_number().over(Window.partitionBy(primary_key).orderBy(F.col("_source_order").desc(), F.col("_record_hash").desc()))).filter(F.col("_rank") == 1).drop("_rank")
        current = current.filter(F.col("_operation") != "D").drop("_operation", "_source_order")
        write_iceberg(current, args["SILVER_DATABASE"], table, f"{warehouse}silver/{table}/")
        if table == "claims":
            claims = current

    if claims is not None:
        fact = claims.drop("description").withColumn("_effective_at", F.current_timestamp())
        write_iceberg(fact, args["GOLD_DATABASE"], "fact_claim_cdc", f"{warehouse}gold/fact_claim_cdc/")
        summary = claims.groupBy("incident_date", "claim_status", "currency_code").agg(
            F.count("claim_id").alias("claim_count"),
            F.sum(F.col("claim_amount").cast(DecimalType(18, 2))).cast(DecimalType(18, 2)).alias("total_claim_amount"),
            F.sum(F.coalesce(F.col("approved_amount").cast(DecimalType(18, 2)), F.lit(0).cast(DecimalType(18, 2)))).cast(DecimalType(18, 2)).alias("total_approved_amount"),
        ).withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn("_source_system", F.lit("insurance_oltp_dms")).withColumn("_ingested_at", F.current_timestamp()).withColumn("_effective_at", F.current_timestamp()).withColumn("_schema_version", F.lit(1)).withColumn("_record_hash", F.sha2(F.concat_ws("||", "incident_date", "claim_status", "currency_code"), 256))
        write_iceberg(summary, args["GOLD_DATABASE"], "claim_daily_summary_cdc", f"{warehouse}gold/claim_daily_summary_cdc/")
    spark.stop()


if __name__ == "__main__":
    main()
