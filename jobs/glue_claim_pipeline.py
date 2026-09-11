"""Stage-dispatched V2 Batch/File Medallion processing for AWS Glue 5.

Terraform creates three Glue jobs from this script and supplies
``PROCESSING_STAGE``. Stable content identity makes a completed file replay a
traceable no-op; Silver owns row DQ/quarantine and Gold owns the completion
marker. The groupings are by operational stage, not one job per table.
"""

from __future__ import annotations

import sys
import hashlib
import json
from urllib.parse import unquote_plus

import boto3
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
OPTIONAL_CLAIM_COLUMNS = [
    "broker_id",
    "claim_type_id",
    "claim_type_code",
    "incident_region_code",
    "coverage_code",
    "vehicle_code",
    "outcome_severity",
    "high_risk_claim",
]
VALID_STATUSES = ["SUBMITTED", "UNDER_REVIEW", "APPROVED", "REJECTED", "PAID", "CLOSED"]
_FAILURE_CONTEXT: dict[str, str] = {}

REFERENCE_DATASETS = {
    "product_master": {
        "key": "product_id",
        "columns": ["product_id", "product_code", "product_name", "product_type", "product_category", "product_status", "effective_from", "effective_to", "base_premium_aud", "coverage_type", "default_excess", "risk_tier", "underwriting_category", "distribution_channel", "max_sum_insured_aud", "max_sum_insured", "active_flag", "expiry_date", "source_updated_at"],
        "dates": ["effective_from", "effective_to", "expiry_date"],
        "decimals": ["base_premium_aud", "default_excess", "max_sum_insured_aud", "max_sum_insured"],
        "integers": ["active_flag"],
        "gold_table": "dim_product_master",
    },
    "broker_master": {
        "key": "broker_id",
        "columns": ["broker_id", "broker_code", "broker_name", "branch_id", "broker_status", "commission_rate", "years_experience", "broker_tier", "active_flag", "effective_date", "source_updated_at"],
        "dates": ["effective_date"], "decimals": ["commission_rate"], "integers": ["years_experience", "active_flag"], "gold_table": "dim_broker",
    },
    "branch_master": {
        "key": "branch_id",
        "columns": ["branch_id", "branch_code", "branch_name", "region_code", "state_code", "city", "branch_status", "manager_code", "active_flag", "source_updated_at"],
        "dates": [], "decimals": [], "integers": ["active_flag"], "gold_table": "dim_branch",
    },
    "claim_type_reference": {
        "key": "claim_type_id",
        "columns": ["claim_type_id", "claim_type_code", "claim_type_name", "product_type", "claim_category", "severity_band", "severity_group", "default_reserve_band", "expected_resolution_days", "high_risk_threshold_aud", "active_flag", "source_updated_at"],
        "dates": [], "decimals": ["high_risk_threshold_aud"], "integers": ["expected_resolution_days", "active_flag"], "gold_table": "dim_claim_type",
    },
    "region_risk_reference": {
        "key": "region_code",
        "columns": ["region_code", "state_code", "region_name", "catastrophe_risk_score", "theft_risk_score", "weather_risk_score", "risk_tier", "urban_rural_class", "accident_risk_score", "natural_hazard_risk_score", "overall_risk_band", "effective_date", "source_updated_at"],
        "dates": ["effective_date"], "decimals": ["catastrophe_risk_score", "theft_risk_score", "weather_risk_score", "accident_risk_score", "natural_hazard_risk_score"], "integers": [], "gold_table": "dim_region_risk",
    },
    "vehicle_reference": {
        "key": "vehicle_code",
        "columns": ["vehicle_code", "make", "model", "model_year", "vehicle_class", "vehicle_type", "market_value_aud", "manufacture_year", "value_band", "engine_size_band", "repair_cost_band", "safety_rating", "theft_risk_score", "theft_risk_band", "risk_category", "source_updated_at"],
        "dates": [], "decimals": ["market_value_aud", "theft_risk_score"], "integers": ["model_year", "manufacture_year", "safety_rating"], "gold_table": "dim_vehicle",
    },
    "coverage_reference": {
        "key": "coverage_code",
        "columns": ["coverage_code", "coverage_name", "product_type", "deductible_aud", "coverage_limit_aud", "coverage_tier", "coverage_category", "default_limit", "default_excess", "optional_flag", "active_flag", "source_updated_at"],
        "dates": [], "decimals": ["deductible_aud", "coverage_limit_aud", "default_limit", "default_excess"], "integers": ["optional_flag", "active_flag"], "gold_table": "dim_coverage",
    },
}


def _optional_arg(name: str, default: str = "") -> str:
    flag = f"--{name}"
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def _file_id(bucket: str, key: str) -> str:
    body = boto3.client("s3").get_object(Bucket=bucket, Key=key)["Body"]
    digest = hashlib.sha256()
    for chunk in iter(lambda: body.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def _control_key(prefix: str, run_id: str, stage: str) -> str:
    return f"{prefix.strip('/')}/pipeline_runs/{run_id}/{stage}.json"


def _processed_key(prefix: str, source_file_id: str) -> str:
    return f"{prefix.strip('/')}/processed_files/{source_file_id}.json"


def _processed_payload(bucket: str, prefix: str, source_file_id: str) -> dict[str, object] | None:
    if not bucket:
        return None
    client = boto3.client("s3")
    try:
        response = client.get_object(Bucket=bucket, Key=_processed_key(prefix, source_file_id))
        return json.loads(response["Body"].read())
    except client.exceptions.ClientError as error:
        if error.response.get("Error", {}).get("Code") in {"404", "NoSuchKey", "NotFound"}:
            return None
        raise


def _run_stage_payload(bucket: str, prefix: str, run_id: str, stage: str) -> dict[str, object] | None:
    if not bucket:
        return None
    client = boto3.client("s3")
    try:
        response = client.get_object(Bucket=bucket, Key=_control_key(prefix, run_id, stage))
        return json.loads(response["Body"].read())
    except client.exceptions.ClientError as error:
        if error.response.get("Error", {}).get("Code") in {"404", "NoSuchKey", "NotFound"}:
            return None
        raise


def _put_json(bucket: str, key: str, payload: dict[str, object]) -> None:
    if bucket:
        boto3.client("s3").put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(payload, sort_keys=True, default=str).encode(),
            ContentType="application/json",
        )


def _audit(
    args: dict[str, str], stage: str, status: str, *, source_file_id: str,
    input_count: int, output_count: int, rejected_count: int = 0,
    duplicate_count: int = 0, error_message: str | None = None,
) -> None:
    reconciled = status != "FAILED" and input_count == output_count + rejected_count + duplicate_count
    payload = {
        "run_id": args["RUN_ID"], "pipeline_name": "batch-file", "source": args["LANDING_KEY"],
        "stage": stage, "status": status, "source_file_id": source_file_id,
        "input_count": input_count, "output_count": output_count,
        "rejected_count": rejected_count, "duplicate_count": duplicate_count,
        "quality_score": round((output_count + duplicate_count) / input_count, 6) if input_count else 1.0,
        "reconciliation_passed": reconciled, "error_message": error_message,
    }
    _put_json(args.get("CONTROL_BUCKET", ""), _control_key(args.get("CONTROL_PREFIX", "control/v2"), args["RUN_ID"], stage), payload)


def _write_quarantine(frame, args: dict[str, str], entity: str) -> int:
    count = frame.count()
    if count and args.get("QUARANTINE_BUCKET"):
        location = (
            f"s3://{args['QUARANTINE_BUCKET']}/{args.get('QUARANTINE_PREFIX', 'quarantine/v2').strip('/')}"
            f"/batch/{entity}/{args['RUN_ID']}/"
        )
        frame.write.mode("overwrite").json(location)
    return count


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


def _process_reference(spark, raw, dataset: str, stage: str, args: dict[str, str], input_uri: str, warehouse: str) -> tuple[int, int, int, int]:
    spec = REFERENCE_DATASETS[dataset]
    if stage == "bronze":
        missing = sorted(set(spec["columns"]) - set(raw.columns))
        if missing:
            raise ValueError(f"{dataset} schema is missing required columns: {','.join(missing)}")
        bronze = raw.select(*spec["columns"]).withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn(
            "_source_system", F.lit("file_reference")
        ).withColumn("_source_object", F.lit(input_uri)).withColumn("_source_file_id", F.lit(args["SOURCE_FILE_ID"])).withColumn(
            "_ingested_at", F.current_timestamp()
        ).withColumn("_schema_version", F.lit(1)).withColumn(
            "_record_hash", F.sha2(F.concat_ws("||", *[F.col(column) for column in spec["columns"]]), 256)
        )
        count = bronze.count()
        _write_iceberg(bronze, args["BRONZE_DATABASE"], dataset, f"{warehouse}bronze/{dataset}/")
        return count, count, 0, 0

    if stage == "gold":
        current = spark.table(f"glue_catalog.{args['SILVER_DATABASE']}.{dataset}")
        gold = current.drop("_source_object").withColumn("_effective_at", F.current_timestamp())
        _write_iceberg(gold, args["GOLD_DATABASE"], spec["gold_table"], f"{warehouse}gold/{spec['gold_table']}/")
        count = gold.count()
        return count, count, 0, 0

    bronze = spark.table(f"glue_catalog.{args['BRONZE_DATABASE']}.{dataset}").filter(
        F.col("_source_file_id") == args["SOURCE_FILE_ID"]
    )
    typed = bronze
    for column in spec["columns"]:
        typed = typed.withColumn(column, F.trim(F.col(column)))
    for column in spec["dates"]:
        typed = typed.withColumn(column, F.to_date(F.col(column)))
    for column in spec["decimals"]:
        typed = typed.withColumn(column, F.col(column).cast(DecimalType(18, 4)))
    for column in spec["integers"]:
        typed = typed.withColumn(column, F.col(column).cast("int"))
    typed = typed.withColumn("source_updated_at", F.to_timestamp("source_updated_at"))
    key = spec["key"]
    invalid = typed.filter(F.col(key).isNull() | (F.col(key) == "")).select(
        F.lit(args["RUN_ID"]).alias("run_id"), F.lit(input_uri).alias("source"),
        F.lit(dataset).alias("entity"), F.to_json(F.struct(*[F.col(c) for c in spec["columns"]])).alias("source_record"),
        F.array(F.lit(f"{key} must not be null or blank")).alias("failed_rules"), F.current_timestamp().alias("rejected_at"),
    )
    rejected = _write_quarantine(invalid, args, dataset)
    accepted = typed.filter(F.col(key).isNotNull() & (F.col(key) != ""))
    accepted_count = accepted.count()
    current = accepted.withColumn(
        "_rank", F.row_number().over(Window.partitionBy(key).orderBy(F.col("source_updated_at").desc(), F.col("_record_hash").desc()))
    ).filter(F.col("_rank") == 1).drop("_rank")
    current_count = current.count()
    duplicates = accepted_count - current_count
    _write_iceberg(current, args["SILVER_DATABASE"], dataset, f"{warehouse}silver/{dataset}/")
    return accepted_count + rejected, current_count, rejected, duplicates


def _table_or_none(spark, database: str, table: str):
    try:
        return spark.table(f"glue_catalog.{database}.{table}")
    except Exception as error:
        if "TABLE_OR_VIEW_NOT_FOUND" in str(error) or "not found" in str(error).lower():
            return None
        raise


def _refresh_enriched_claims(spark, args: dict[str, str], warehouse: str) -> None:
    silver = args["SILVER_DATABASE"]
    required = {
        "c": "claim", "p": "policies", "op": "products", "cu": "customers",
        "pm": "product_master", "b": "broker_master", "br": "branch_master",
        "ct": "claim_type_reference", "rr": "region_risk_reference",
        "v": "vehicle_reference", "cv": "coverage_reference",
    }
    frames = {alias: _table_or_none(spark, silver, table) for alias, table in required.items()}
    if any(frame is None for frame in frames.values()):
        return
    f = {alias: frame.alias(alias) for alias, frame in frames.items()}
    joined = (
        f["c"].join(f["p"], F.col("c.policy_id") == F.col("p.policy_id"), "inner")
        .join(f["op"], F.col("p.product_id") == F.col("op.product_id"), "inner")
        .join(f["cu"], F.col("c.customer_id") == F.col("cu.customer_id"), "inner")
        .join(f["pm"], F.col("p.product_id") == F.col("pm.product_id"), "left")
        .join(f["b"], F.col("c.broker_id") == F.col("b.broker_id"), "left")
        .join(f["br"], F.col("b.branch_id") == F.col("br.branch_id"), "left")
        .join(f["ct"], F.col("c.claim_type_id") == F.col("ct.claim_type_id"), "left")
        .join(f["rr"], F.col("c.incident_region_code") == F.col("rr.region_code"), "left")
        .join(f["v"], F.col("c.vehicle_code") == F.col("v.vehicle_code"), "left")
        .join(f["cv"], F.col("c.coverage_code") == F.col("cv.coverage_code"), "left")
    )
    enriched = joined.select(
        F.col("c.claim_id"), F.col("c.claim_number"), F.col("c.policy_id"), F.col("c.customer_id"),
        F.col("p.product_id"), F.col("op.product_code"), F.col("pm.product_name"), F.col("pm.product_type"),
        F.col("p.premium_amount").cast(DecimalType(18, 2)).alias("annual_premium_amount"),
        F.col("pm.product_category"), F.col("pm.coverage_type"), F.col("pm.default_excess").alias("product_default_excess"),
        F.col("pm.max_sum_insured"), F.col("pm.risk_tier").alias("product_risk_tier"),
        F.col("c.broker_id"), F.col("b.broker_name"), F.col("b.years_experience"), F.col("b.broker_tier"),
        F.col("b.branch_id"), F.col("br.branch_name"), F.col("br.state_code").alias("broker_state_code"), F.col("br.region_code").alias("broker_region_code"),
        F.col("c.claim_type_id"), F.col("c.claim_type_code"), F.col("ct.claim_type_name"), F.col("ct.claim_category"), F.col("ct.severity_band"),
        F.col("c.incident_region_code"), F.col("rr.region_name").alias("incident_region_name"),
        F.col("rr.catastrophe_risk_score"), F.col("rr.theft_risk_score").alias("region_theft_risk_score"), F.col("rr.weather_risk_score"),
        F.col("rr.accident_risk_score"), F.col("rr.natural_hazard_risk_score"), F.col("rr.overall_risk_band"),
        F.col("c.coverage_code"), F.col("cv.coverage_tier"), F.col("cv.coverage_category"), F.col("cv.deductible_aud"), F.col("cv.coverage_limit_aud"), F.col("cv.optional_flag"),
        F.col("c.vehicle_code"), F.col("v.vehicle_class"), F.col("v.model_year"), F.col("v.market_value_aud"), F.col("v.safety_rating"),
        F.col("v.repair_cost_band"), F.col("v.theft_risk_band"), F.col("v.risk_category").alias("vehicle_risk_category"),
        F.col("c.incident_date"), F.col("c.submitted_at"), F.col("c.claim_amount").cast(DecimalType(18, 2)).alias("claim_amount"),
        F.col("c.approved_amount").cast(DecimalType(18, 2)).alias("approved_amount"), F.col("c.claim_status"), F.col("c.currency_code"),
        F.col("c.outcome_severity"), F.col("c.high_risk_claim").cast("int").alias("high_risk_claim"),
        F.col("c._run_id"), F.col("c._ingested_at"), F.current_timestamp().alias("_effective_at"),
    )
    _write_iceberg(enriched, args["GOLD_DATABASE"], "fact_claim_enriched", f"{warehouse}gold/fact_claim_enriched/")
    features = enriched.select(
        "claim_id", "product_id", "product_type", "product_category", "product_risk_tier", "broker_id", "years_experience", "broker_tier", "branch_id", "broker_region_code",
        "claim_type_id", "claim_type_code", "claim_category", "incident_region_code", "catastrophe_risk_score", "region_theft_risk_score", "weather_risk_score", "accident_risk_score", "natural_hazard_risk_score", "overall_risk_band",
        "coverage_code", "coverage_tier", "coverage_category", "deductible_aud", "coverage_limit_aud", "optional_flag", "vehicle_code", "vehicle_class",
        "model_year", "market_value_aud", "safety_rating", "repair_cost_band", "theft_risk_band", "vehicle_risk_category", "incident_date", "submitted_at", "claim_amount", "high_risk_claim",
        "_run_id", "_ingested_at", "_effective_at",
    ).withColumn("vehicle_age", F.when(F.col("model_year").isNotNull(), F.year("submitted_at") - F.col("model_year")))
    _write_iceberg(features, args["GOLD_DATABASE"], "claim_risk_features", f"{warehouse}gold/claim_risk_features/")

    policy_performance = enriched.groupBy(
        "policy_id", "product_id", "product_type", "product_category", "broker_id", "broker_name", "branch_id", "branch_name", "broker_region_code", "currency_code"
    ).agg(
        F.first("annual_premium_amount", ignorenulls=True).alias("annual_premium_amount"),
        F.countDistinct("claim_id").alias("claim_count"),
        F.sum("claim_amount").cast(DecimalType(18, 2)).alias("total_claim_amount"),
        F.sum(F.coalesce(F.col("approved_amount"), F.lit(0).cast(DecimalType(18, 2)))).cast(DecimalType(18, 2)).alias("total_approved_amount"),
        F.max("submitted_at").alias("latest_claim_submitted_at"),
    ).withColumn(
        "loss_ratio", F.when(F.col("annual_premium_amount") > 0, F.col("total_approved_amount") / F.col("annual_premium_amount"))
    ).withColumn("_effective_at", F.current_timestamp())
    _write_iceberg(policy_performance, args["GOLD_DATABASE"], "policy_performance", f"{warehouse}gold/policy_performance/")

    broker_performance = policy_performance.groupBy("broker_id", "broker_name", "branch_id", "branch_name", "broker_region_code", "currency_code").agg(
        F.countDistinct("policy_id").alias("active_policy_count"),
        F.sum("annual_premium_amount").cast(DecimalType(18, 2)).alias("total_annual_premium"),
        F.sum("claim_count").alias("claim_count"),
        F.sum("total_claim_amount").cast(DecimalType(18, 2)).alias("total_claim_amount"),
        F.sum("total_approved_amount").cast(DecimalType(18, 2)).alias("total_approved_amount"),
    ).withColumn(
        "loss_ratio", F.when(F.col("total_annual_premium") > 0, F.col("total_approved_amount") / F.col("total_annual_premium"))
    ).withColumn("_effective_at", F.current_timestamp())
    _write_iceberg(broker_performance, args["GOLD_DATABASE"], "broker_performance", f"{warehouse}gold/broker_performance/")


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
    args.update(
        {
            "PROCESSING_STAGE": _optional_arg("PROCESSING_STAGE", "all").lower(),
            "CONTROL_BUCKET": _optional_arg("CONTROL_BUCKET"),
            "QUARANTINE_BUCKET": _optional_arg("QUARANTINE_BUCKET"),
            "CONTROL_PREFIX": _optional_arg("CONTROL_PREFIX", "control/v2"),
            "QUARANTINE_PREFIX": _optional_arg("QUARANTINE_PREFIX", "quarantine/v2"),
        }
    )
    stage = args["PROCESSING_STAGE"]
    if stage not in {"bronze", "silver", "gold", "all"}:
        raise ValueError(f"unsupported PROCESSING_STAGE: {stage}")
    _FAILURE_CONTEXT.update(args)
    landing_bucket = args["LANDING_BUCKET"]
    landing_key = unquote_plus(args["LANDING_KEY"])
    run_id = args["RUN_ID"]
    lakehouse_bucket = args["LAKEHOUSE_BUCKET"]
    input_uri = f"s3://{landing_bucket}/{landing_key}"
    warehouse = f"s3://{lakehouse_bucket}/lakehouse/"
    args["SOURCE_FILE_ID"] = _file_id(landing_bucket, landing_key)
    _FAILURE_CONTEXT.update(args)
    completed = _processed_payload(args["CONTROL_BUCKET"], args["CONTROL_PREFIX"], args["SOURCE_FILE_ID"])
    if completed:
        prior_count = int(completed.get("input_count", 0))
        stages = [stage] if stage != "all" else ["bronze", "silver", "gold"]
        for duplicate_stage in stages:
            _audit(
                args, duplicate_stage, "DUPLICATE", source_file_id=args["SOURCE_FILE_ID"],
                input_count=prior_count, output_count=0, duplicate_count=prior_count,
            )
        return

    spark = (
        SparkSession.builder.config("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
        .config("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        .config("spark.sql.catalog.glue_catalog.warehouse", warehouse)
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .getOrCreate()
    )

    landing_name = landing_key.rsplit("/", 1)[-1].lower()
    dataset = next((name for name in REFERENCE_DATASETS if landing_name == f"{name}.csv"), None)
    if not landing_name.startswith("broker_claims") or not landing_name.endswith(".csv"):
        if not dataset:
            raise ValueError(f"unsupported V2 file dataset: {landing_name}")

    requested_stages = [stage] if stage != "all" else ["bronze", "silver", "gold"]
    for current_stage in requested_stages:
        raw = None
        if current_stage == "bronze":
            raw = spark.read.option("header", "true").option("mode", "FAILFAST").csv(input_uri)
        if dataset:
            counts = _process_reference(spark, raw, dataset, current_stage, args, input_uri, warehouse)
            _audit(
                args, current_stage, "SUCCEEDED", source_file_id=args["SOURCE_FILE_ID"],
                input_count=counts[0], output_count=counts[1], rejected_count=counts[2], duplicate_count=counts[3],
            )
            if current_stage == "gold":
                silver_audit = _run_stage_payload(args["CONTROL_BUCKET"], args["CONTROL_PREFIX"], run_id, "silver") or {}
                _put_json(
                    args["CONTROL_BUCKET"], _processed_key(args["CONTROL_PREFIX"], args["SOURCE_FILE_ID"]),
                    {"source_file_id": args["SOURCE_FILE_ID"], "source": input_uri, "run_id": run_id, "input_count": int(silver_audit.get("input_count", counts[0])), "status": "SUCCEEDED"},
                )
            continue

        if current_stage == "bronze":
            missing = sorted(set(REQUIRED_COLUMNS) - set(raw.columns))
            if missing:
                raise ValueError(f"broker claim schema is missing required columns: {','.join(missing)}")
            if landing_name == "broker_claims.csv":
                missing_optional = sorted(set(OPTIONAL_CLAIM_COLUMNS) - set(raw.columns))
                if missing_optional:
                    raise ValueError(f"expanded broker claim schema is missing columns: {','.join(missing_optional)}")
            claim_columns = REQUIRED_COLUMNS + [column for column in OPTIONAL_CLAIM_COLUMNS if column in raw.columns]
            bronze = raw.select(*claim_columns).withColumn("_run_id", F.lit(run_id)).withColumn(
                "_source_system", F.lit("broker_csv")
            ).withColumn("_source_object", F.lit(input_uri)).withColumn("_source_file_id", F.lit(args["SOURCE_FILE_ID"])).withColumn(
                "_ingested_at", F.current_timestamp()
            ).withColumn("_schema_version", F.lit(2)).withColumn(
                "_record_hash", F.sha2(F.concat_ws("||", *[F.col(column) for column in claim_columns]), 256)
            )
            input_count = bronze.count()
            _write_iceberg(bronze, args["BRONZE_DATABASE"], "claim", f"{warehouse}bronze/claim/")
            _audit(args, "bronze", "SUCCEEDED", source_file_id=args["SOURCE_FILE_ID"], input_count=input_count, output_count=input_count)
            continue

        if current_stage == "gold":
            latest = spark.table(f"glue_catalog.{args['SILVER_DATABASE']}.claim")
            fact = latest.drop("description").withColumn("_effective_at", F.current_timestamp())
            _write_iceberg(fact, args["GOLD_DATABASE"], "fact_claim", f"{warehouse}gold/fact_claim/")
            summary = latest.groupBy("incident_date", "claim_status", "currency_code").agg(
                F.count("claim_id").alias("claim_count"),
                F.sum("claim_amount").cast(DecimalType(18, 2)).alias("total_claim_amount"),
                F.sum(F.coalesce(F.col("approved_amount"), F.lit(0).cast(DecimalType(18, 2)))).cast(DecimalType(18, 2)).alias("total_approved_amount"),
            ).withColumn("_run_id", F.lit(run_id)).withColumn("_source_system", F.lit("broker_csv")).withColumn(
                "_ingested_at", F.current_timestamp()
            ).withColumn("_effective_at", F.current_timestamp()).withColumn("_schema_version", F.lit(2)).withColumn(
                "_record_hash", F.sha2(F.concat_ws("||", "incident_date", "claim_status", "currency_code"), 256)
            )
            _write_iceberg(summary, args["GOLD_DATABASE"], "claim_daily_summary", f"{warehouse}gold/claim_daily_summary/")
            if set(OPTIONAL_CLAIM_COLUMNS).issubset(set(latest.columns)):
                _refresh_enriched_claims(spark, args, warehouse)
            output_count = latest.count()
            _audit(args, "gold", "SUCCEEDED", source_file_id=args["SOURCE_FILE_ID"], input_count=output_count, output_count=output_count)
            silver_audit = _run_stage_payload(args["CONTROL_BUCKET"], args["CONTROL_PREFIX"], run_id, "silver") or {}
            _put_json(
                args["CONTROL_BUCKET"], _processed_key(args["CONTROL_PREFIX"], args["SOURCE_FILE_ID"]),
                {"source_file_id": args["SOURCE_FILE_ID"], "source": input_uri, "run_id": run_id, "input_count": int(silver_audit.get("input_count", output_count)), "status": "SUCCEEDED"},
            )
            continue

        bronze = spark.table(f"glue_catalog.{args['BRONZE_DATABASE']}.claim").filter(
            F.col("_source_file_id") == args["SOURCE_FILE_ID"]
        )
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
        for column in [name for name in OPTIONAL_CLAIM_COLUMNS if name in bronze.columns and name != "high_risk_claim"]:
            typed = typed.withColumn(column, F.trim(F.col(column)))
        if "high_risk_claim" in bronze.columns:
            typed = typed.withColumn("high_risk_claim", F.col("high_risk_claim").cast("int"))
        valid_condition = F.coalesce((
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
        ), F.lit(False))
        invalid = typed.filter(~valid_condition).select(
            F.lit(run_id).alias("run_id"), F.lit(input_uri).alias("source"), F.lit("claim").alias("entity"),
            F.to_json(F.struct(*[F.col(c) for c in REQUIRED_COLUMNS])).alias("source_record"),
            F.array(F.lit("claim_contract_v2")).alias("failed_rules"), F.current_timestamp().alias("rejected_at"),
        )
        rejected_count = _write_quarantine(invalid, args, "claim")
        valid = typed.filter(valid_condition)
        valid_count = valid.count()
        latest = valid.withColumn(
            "_rank", F.row_number().over(Window.partitionBy("claim_id").orderBy(F.col("updated_at").desc(), F.col("_record_hash").desc()))
        ).filter(F.col("_rank") == 1).drop("_rank")
        output_count = latest.count()
        duplicate_count = valid_count - output_count
        _write_iceberg(latest, args["SILVER_DATABASE"], "claim", f"{warehouse}silver/claim/")
        _audit(
            args, "silver", "SUCCEEDED", source_file_id=args["SOURCE_FILE_ID"],
            input_count=valid_count + rejected_count, output_count=output_count,
            rejected_count=rejected_count, duplicate_count=duplicate_count,
        )
    spark.stop()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        if _FAILURE_CONTEXT:
            try:
                _audit(
                    _FAILURE_CONTEXT,
                    _FAILURE_CONTEXT.get("PROCESSING_STAGE", "unknown"),
                    "FAILED",
                    source_file_id=_FAILURE_CONTEXT.get("SOURCE_FILE_ID", "unknown"),
                    input_count=0,
                    output_count=0,
                    error_message=str(error),
                )
            except Exception:
                # Never mask the original processing failure if audit persistence
                # is also unavailable; Glue and Step Functions retain it.
                pass
        raise
