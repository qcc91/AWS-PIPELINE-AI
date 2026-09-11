import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEV = (ROOT / "terraform/environments/dev/main.tf").read_text(encoding="utf-8")
BATCH = (ROOT / "terraform/modules/batch-ingestion/main.tf").read_text(encoding="utf-8")
CDC = (ROOT / "terraform/modules/cdc/main.tf").read_text(encoding="utf-8")


def test_streaming_is_retired_from_active_terraform():
    assert 'module "streaming"' not in DEV
    assert not list((ROOT / "terraform/modules/streaming").glob("*.tf"))
    for token in ("aws_kinesis_stream", "aws_kinesis_firehose_delivery_stream"):
        assert token not in DEV


def test_batch_has_independent_medallion_jobs():
    assert 'resource "aws_glue_job" "batch"' in BATCH
    assert 'resource "aws_glue_job" "stage"' in BATCH
    for stage in ("bronze", "silver", "gold"):
        assert stage in BATCH
    assert '"--PROCESSING_STAGE"' in BATCH


def test_cdc_has_independent_medallion_jobs():
    assert 'resource "aws_glue_job" "cdc"' in CDC
    assert 'resource "aws_glue_job" "cdc_stage"' in CDC
    for stage in ("bronze", "silver", "gold"):
        assert stage in CDC
    assert '"--PROCESSING_STAGE"' in CDC


def test_orchestrators_use_bounded_retry_catch_and_fail():
    for module in (BATCH, CDC):
        # Step Functions MaxAttempts counts retries, so 2 means 3 total attempts.
        assert module.count("MaxAttempts     = 2") == 3
        assert module.count("BackoffRate     = 2.0") == 3
        assert module.count('ErrorEquals = ["States.ALL"]') >= 6
        assert "States.TaskFailed" not in module
        assert module.count('Resource = "arn:aws:states:::aws-sdk:s3:putObject"') == 3
        assert module.count("-failure.json") == 3
        assert 'Type  = "Fail"' in module
        assert 'Next  = "RunSilver"' in module
        assert 'Next  = "RunGold"' in module


def test_control_and_quarantine_contract_is_passed_without_delete_access():
    for module in (BATCH, CDC):
        assert '"--CONTROL_BUCKET"' in module
        assert '"--CONTROL_PREFIX"' in module
        assert '"--QUARANTINE_BUCKET"' in module
        assert '"--QUARANTINE_PREFIX"' in module
        statement = re.search(
            r'Action\s*=\s*\["s3:GetObject",\s*"s3:GetObjectVersion",\s*"s3:PutObject"\],?\s*Resource\s*=\s*"\$\{local\.quarantine_bucket_arn\}/quarantine/v2/\*"',
            module,
        )
        assert statement is not None
        assert "s3:DeleteObject" not in statement.group(0)
