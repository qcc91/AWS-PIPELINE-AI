from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "terraform/modules/batch-ingestion/main.tf").read_text(encoding="utf-8")
DEV_MAIN = (ROOT / "terraform/environments/dev/main.tf").read_text(encoding="utf-8")
JOB = (ROOT / "jobs/glue_claim_pipeline.py").read_text(encoding="utf-8")


def test_all_layers_are_iceberg_and_paths_are_stable():
    assert MODULE.count('aws_glue_job"') == 1
    for layer in ("bronze", "silver", "gold"):
        assert layer in MODULE
    assert JOB.count(".using(\"iceberg\")") == 1
    assert 'bronze/claim/' in JOB
    assert 'silver/claim/' in JOB
    assert 'gold/fact_claim/' in JOB
    assert 'gold/claim_daily_summary/' in JOB


def test_eventbridge_stepfunctions_glue_contract_is_explicit():
    assert "aws_s3_bucket_notification" in MODULE
    assert 'eventbridge = true' in MODULE
    assert "aws_cloudwatch_event_rule" in MODULE
    assert 'source      = ["aws.s3"]' in MODULE
    assert "aws_sfn_state_machine" in MODULE
    assert "arn:aws:states:::glue:startJobRun.sync" in MODULE
    for argument in ("LANDING_BUCKET", "LANDING_KEY", "RUN_ID"):
        assert f'"--{argument}.$"' in MODULE


def test_review_corrections_are_present():
    assert "source_hash" in MODULE
    assert "etag" not in MODULE
    assert "glue:GetJobRuns" in MODULE
    assert 'Resource = "*"' in MODULE
    assert '"--continuous-log-logGroup"' in MODULE
    assert '"--conf"' in MODULE
    assert "spark.sql.catalog.glue_catalog.io-impl" in MODULE
    assert "spark.sql.catalog.glue_catalog.io-impl" in JOB
    assert "spark.sql.catalog.glue_catalog.catalog-impl" in JOB
    assert "enable-glue-datacatalog" not in MODULE
    assert re.search(r"user_role_arns\s*=\s*\[\]", DEV_MAIN)


def test_no_credentials_or_forbidden_always_on_services():
    combined = MODULE + JOB
    for forbidden in ("access_key", "secret_key", "password", "nat_gateway", "internet_gateway", "aws_instance"):
        assert forbidden not in combined.lower()
    assert 'Principal = "*"' not in MODULE
