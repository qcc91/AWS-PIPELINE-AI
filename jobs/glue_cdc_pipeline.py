"""Stage-dispatched V2 DMS CDC reliability pipeline for AWS Glue 5."""

from __future__ import annotations

import json
import sys

import boto3
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

TABLES = {"customers": "customer_id", "products": "product_id", "policies": "policy_id", "claims": "claim_id", "payments": "payment_id"}
VALID_OPERATIONS = ["I", "U", "D"]


def _optional_arg(name: str, default: str = "") -> str:
    flag = f"--{name}"
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def _put_json(bucket: str, key: str, payload: dict[str, object]) -> None:
    if bucket:
        boto3.client("s3").put_object(Bucket=bucket, Key=key, Body=json.dumps(payload, sort_keys=True, default=str).encode(), ContentType="application/json")


def _audit(args: dict[str, str], stage: str, status: str, counts: dict[str, int], error: str | None = None) -> None:
    _put_json(args.get("CONTROL_BUCKET", ""), f"{args.get('CONTROL_PREFIX', 'control/v2').strip('/')}/pipeline_runs/{args['RUN_ID']}/{stage}.json", {
        "run_id": args["RUN_ID"], "pipeline_name": "postgresql-cdc", "source": args["CDC_OBJECT_KEY"], "stage": stage,
        "status": status, "input_count": counts.get("input", 0), "output_count": counts.get("output", 0),
        "rejected_count": counts.get("rejected", 0), "duplicate_count": counts.get("duplicate", 0), "error_message": error,
        "reconciliation_type": "change-log-to-current-state", "reconciliation_passed": status != "FAILED" and counts.get("input", 0) >= counts.get("rejected", 0) + counts.get("duplicate", 0),
    })


def _write_quarantine(frame, args: dict[str, str], table: str) -> int:
    count = frame.count()
    if count and args.get("QUARANTINE_BUCKET"):
        frame.write.mode("overwrite").json(f"s3://{args['QUARANTINE_BUCKET']}/{args.get('QUARANTINE_PREFIX', 'quarantine/v2').strip('/')}/cdc/{table}/{args['RUN_ID']}/")
    return count


def write_iceberg(frame, database: str, table: str, location: str) -> None:
    (frame.writeTo(f"glue_catalog.{database}.{table}").using("iceberg").tableProperty("format-version", "2").tableProperty("write.format.default", "parquet").tableProperty("location", location).createOrReplace())


def _source_fields(raw):
    op_column = next((name for name in ["Op", "op", "operation"] if name in raw.columns), None)
    timestamp_column = next((name for name in ["_dms_timestamp", "updated_at"] if name in raw.columns), None)
    operation = F.upper(F.coalesce(F.col(op_column), F.lit("I"))) if op_column else F.lit("I")
    event_time = F.to_timestamp(F.col(timestamp_column)) if timestamp_column else F.current_timestamp()
    return operation, event_time


def _business_validity(table: str):
    key = TABLES[table]
    base = F.col(key).isNotNull() & (F.trim(F.col(key)) != "") & F.col("_operation").isin(VALID_OPERATIONS) & F.col("_source_order").isNotNull()
    business = F.lit(True)
    if table == "policies":
        business = (F.col("premium_amount").cast(DecimalType(18, 2)) >= 0) & (F.to_date("start_date") < F.to_date("end_date"))
    elif table == "claims":
        business = (F.col("claim_amount").cast(DecimalType(18, 2)) >= 0) & (F.col("approved_amount").isNull() | (F.col("approved_amount").cast(DecimalType(18, 2)) >= 0)) & (F.to_date("incident_date") <= F.to_date("submitted_at"))
    elif table == "payments":
        business = F.col("payment_amount").cast(DecimalType(18, 2)) >= 0
    # Tombstones may contain only the primary key. Business-field validation is
    # for live I/U records and must never suppress a legitimate delete.
    return base & ((F.col("_operation") == "D") | business)


def _bronze(spark, args: dict[str, str], warehouse: str) -> dict[str, int]:
    root = f"s3://{args['LANDING_BUCKET']}/{args['CDC_PREFIX'].strip('/')}/public"
    counts = {"input": 0, "output": 0, "rejected": 0, "duplicate": 0}
    for table, primary_key in TABLES.items():
        path = f"{root}/{table}/"
        try:
            raw = spark.read.option("header", "true").option("inferSchema", "false").csv(path)
        except Exception as error:
            if "Path does not exist" in str(error) or "PATH_NOT_FOUND" in str(error):
                continue
            raise
        if not raw.columns or primary_key not in raw.columns:
            continue
        operation, event_time = _source_fields(raw)
        bronze = raw.withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn("_source_system", F.lit("insurance_oltp_dms")).withColumn("_source_object", F.lit(path)).withColumn("_ingested_at", F.current_timestamp()).withColumn("_schema_version", F.lit(2)).withColumn("_operation", operation).withColumn("_source_order", event_time)
        identity_columns = [F.coalesce(F.col(name).cast("string"), F.lit("<NULL>")) for name in raw.columns]
        bronze = bronze.withColumn("_source_change_id", F.sha2(F.concat_ws("||", F.lit(table), F.col(primary_key), F.col("_operation"), F.col("_source_order").cast("string"), *identity_columns), 256)).withColumn("_record_hash", F.col("_source_change_id"))
        input_count = bronze.count()
        valid_condition = F.coalesce(_business_validity(table), F.lit(False))
        invalid = bronze.filter(~valid_condition).select(F.lit(args["RUN_ID"]).alias("run_id"), F.lit(path).alias("source"), F.lit(table).alias("entity"), F.to_json(F.struct(*[F.col(name) for name in raw.columns])).alias("source_record"), F.array(F.lit(f"{table}_cdc_contract_v2")).alias("failed_rules"), F.current_timestamp().alias("rejected_at"))
        rejected = _write_quarantine(invalid, args, table)
        valid = bronze.filter(valid_condition)
        valid_count = valid.count()
        deduped = valid.dropDuplicates(["_source_change_id"])
        output_count = deduped.count()
        write_iceberg(deduped, args["BRONZE_DATABASE"], f"{table}_cdc", f"{warehouse}bronze/{table}_cdc/")
        counts["input"] += input_count; counts["output"] += output_count; counts["rejected"] += rejected; counts["duplicate"] += valid_count - output_count
    return counts


def _silver(spark, args: dict[str, str], warehouse: str) -> dict[str, int]:
    counts = {"input": 0, "output": 0, "rejected": 0, "duplicate": 0}
    for table, primary_key in TABLES.items():
        try:
            changes = spark.table(f"glue_catalog.{args['BRONZE_DATABASE']}.{table}_cdc")
        except Exception as error:
            if "not found" in str(error).lower():
                continue
            raise
        input_count = changes.count()
        current_with_deletes = changes.withColumn("_rank", F.row_number().over(Window.partitionBy(primary_key).orderBy(F.col("_source_order").desc(), F.col("_source_change_id").desc()))).filter(F.col("_rank") == 1).drop("_rank")
        current = current_with_deletes.filter(F.col("_operation") != "D")
        output_count = current.count()
        write_iceberg(current, args["SILVER_DATABASE"], table, f"{warehouse}silver/{table}/")
        counts["input"] += input_count; counts["output"] += output_count; counts["duplicate"] += input_count - current_with_deletes.count()
    return counts


def _gold(spark, args: dict[str, str], warehouse: str) -> dict[str, int]:
    claims = spark.table(f"glue_catalog.{args['SILVER_DATABASE']}.claims")
    fact = claims.drop("description", "_operation", "_source_order").withColumn("_effective_at", F.current_timestamp())
    write_iceberg(fact, args["GOLD_DATABASE"], "fact_claim_cdc", f"{warehouse}gold/fact_claim_cdc/")
    summary = claims.groupBy("incident_date", "claim_status", "currency_code").agg(F.count("claim_id").alias("claim_count"), F.sum(F.col("claim_amount").cast(DecimalType(18, 2))).cast(DecimalType(18, 2)).alias("total_claim_amount"), F.sum(F.coalesce(F.col("approved_amount").cast(DecimalType(18, 2)), F.lit(0).cast(DecimalType(18, 2)))).cast(DecimalType(18, 2)).alias("total_approved_amount")).withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn("_source_system", F.lit("insurance_oltp_dms")).withColumn("_ingested_at", F.current_timestamp()).withColumn("_effective_at", F.current_timestamp()).withColumn("_schema_version", F.lit(2)).withColumn("_record_hash", F.sha2(F.concat_ws("||", "incident_date", "claim_status", "currency_code"), 256))
    write_iceberg(summary, args["GOLD_DATABASE"], "claim_daily_summary_cdc", f"{warehouse}gold/claim_daily_summary_cdc/")
    count = claims.count()
    return {"input": count, "output": count, "rejected": 0, "duplicate": 0}


def main() -> None:
    args = getResolvedOptions(sys.argv, ["JOB_NAME", "LANDING_BUCKET", "CDC_PREFIX", "CDC_OBJECT_KEY", "RUN_ID", "LAKEHOUSE_BUCKET", "BRONZE_DATABASE", "SILVER_DATABASE", "GOLD_DATABASE"])
    args.update({"PROCESSING_STAGE": _optional_arg("PROCESSING_STAGE", "all").lower(), "CONTROL_BUCKET": _optional_arg("CONTROL_BUCKET"), "QUARANTINE_BUCKET": _optional_arg("QUARANTINE_BUCKET"), "CONTROL_PREFIX": _optional_arg("CONTROL_PREFIX", "control/v2"), "QUARANTINE_PREFIX": _optional_arg("QUARANTINE_PREFIX", "quarantine/v2")})
    stage = args["PROCESSING_STAGE"]
    if stage not in {"bronze", "silver", "gold", "all"}:
        raise ValueError(f"unsupported PROCESSING_STAGE: {stage}")
    warehouse = f"s3://{args['LAKEHOUSE_BUCKET']}/lakehouse/"
    spark = (SparkSession.builder.config("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog").config("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog").config("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO").config("spark.sql.catalog.glue_catalog.warehouse", warehouse).config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions").getOrCreate())
    handlers = {"bronze": _bronze, "silver": _silver, "gold": _gold}
    stages = [stage] if stage != "all" else ["bronze", "silver", "gold"]
    current_stage = stages[0]
    try:
        for current_stage in stages:
            _audit(args, current_stage, "SUCCEEDED", handlers[current_stage](spark, args, warehouse))
    except Exception as error:
        _audit(args, current_stage, "FAILED", {"input": 0, "output": 0, "rejected": 0, "duplicate": 0}, str(error))
        raise
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
