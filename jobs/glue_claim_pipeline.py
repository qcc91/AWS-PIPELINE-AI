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


def _process_reference(raw, dataset: str, args: dict[str, str], input_uri: str, warehouse: str) -> None:
    spec = REFERENCE_DATASETS[dataset]
    missing = sorted(set(spec["columns"]) - set(raw.columns))
    if missing:
        raise ValueError(f"{dataset} schema is missing required columns: {','.join(missing)}")
    ingested_at = F.current_timestamp()
    bronze = raw.select(*spec["columns"]).withColumn("_run_id", F.lit(args["RUN_ID"])).withColumn(
        "_source_system", F.lit("file_reference")
    ).withColumn("_source_object", F.lit(input_uri)).withColumn("_ingested_at", ingested_at).withColumn(
        "_schema_version", F.lit(1)
    ).withColumn("_record_hash", F.sha2(F.concat_ws("||", *[F.col(column) for column in spec["columns"]]), 256))
    _write_iceberg(bronze, args["BRONZE_DATABASE"], dataset, f"{warehouse}bronze/{dataset}/")

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
    current = typed.filter(F.col(key).isNotNull() & (F.col(key) != "")).withColumn(
        "_rank", F.row_number().over(Window.partitionBy(key).orderBy(F.col("source_updated_at").desc(), F.col("_record_hash").desc()))
    ).filter(F.col("_rank") == 1).drop("_rank")
    _write_iceberg(current, args["SILVER_DATABASE"], dataset, f"{warehouse}silver/{dataset}/")
    gold = current.drop("_source_object").withColumn("_effective_at", F.current_timestamp())
    _write_iceberg(gold, args["GOLD_DATABASE"], spec["gold_table"], f"{warehouse}gold/{spec['gold_table']}/")


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
    landing_name = landing_key.rsplit("/", 1)[-1].lower()
    dataset = next((name for name in REFERENCE_DATASETS if landing_name == f"{name}.csv"), None)
    if dataset:
        _process_reference(raw, dataset, args, input_uri, warehouse)
        spark.stop()
        return
    if not landing_name.startswith("broker_claims") or not landing_name.endswith(".csv"):
        raise ValueError(f"unsupported V1 file dataset: {landing_name}")
    missing = sorted(set(REQUIRED_COLUMNS) - set(raw.columns))
    if missing:
        raise ValueError(f"broker claim schema is missing required columns: {','.join(missing)}")
    if landing_name == "broker_claims.csv":
        missing_optional = sorted(set(OPTIONAL_CLAIM_COLUMNS) - set(raw.columns))
        if missing_optional:
            raise ValueError(f"expanded broker claim schema is missing columns: {','.join(missing_optional)}")

    ingested_at = F.current_timestamp()
    claim_columns = REQUIRED_COLUMNS + [column for column in OPTIONAL_CLAIM_COLUMNS if column in raw.columns]
    bronze = raw.select(*claim_columns).withColumn("_run_id", F.lit(run_id)).withColumn(
        "_source_system", F.lit("broker_csv")
    ).withColumn("_source_object", F.lit(input_uri)).withColumn("_ingested_at", ingested_at).withColumn(
        "_schema_version", F.lit(1)
    ).withColumn("_record_hash", F.sha2(F.concat_ws("||", *[F.col(column) for column in claim_columns]), 256))
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
    for column in [name for name in OPTIONAL_CLAIM_COLUMNS if name in raw.columns and name != "high_risk_claim"]:
        typed = typed.withColumn(column, F.trim(F.col(column)))
    if "high_risk_claim" in raw.columns:
        typed = typed.withColumn("high_risk_claim", F.col("high_risk_claim").cast("int"))
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
    if set(OPTIONAL_CLAIM_COLUMNS).issubset(set(raw.columns)):
        _refresh_enriched_claims(spark, args, warehouse)
    spark.stop()


if __name__ == "__main__":
    main()
