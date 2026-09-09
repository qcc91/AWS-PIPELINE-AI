from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "terraform/modules/streaming/main.tf").read_text(encoding="utf-8")
JOB = (ROOT / "jobs/glue_streaming_pipeline.py").read_text(encoding="utf-8")


def test_streaming_chain_and_encryption_are_declared():
    for resource in ("aws_kinesis_stream", "aws_kinesis_firehose_delivery_stream", "aws_iam_role", "aws_iam_role_policy"):
        assert resource in MODULE
    assert "kinesis_source_configuration" in MODULE
    assert 'encryption_type  = "KMS"' in MODULE
    assert "kms_key_arn" in MODULE
    assert "kinesis:GetRecords" in MODULE
    assert "kinesis:GetShardIterator" in MODULE
    assert "kinesis:PutRecord" in MODULE


def test_event_contract_and_iceberg_outputs_are_explicit():
    for field in ("event_id", "event_type", "event_timestamp", "source", "payload"):
        assert field in JOB
    assert JOB.count('using("iceberg")') == 1
    assert "bronze/stream_event/" in JOB
    assert "silver/stream_event/" in JOB
    assert "gold/event_daily_summary/" in JOB
