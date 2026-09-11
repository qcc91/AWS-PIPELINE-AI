"""Focused V2 acceptance checks for the inline Glue DQDL gates."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BATCH = (ROOT / "jobs" / "glue_claim_pipeline.py").read_text(encoding="utf-8")
CDC = (ROOT / "jobs" / "glue_cdc_pipeline.py").read_text(encoding="utf-8")


def test_batch_claim_dqdl_is_small_and_runs_before_silver_write():
    assert 'IsComplete "claim_id"' in BATCH
    assert 'IsUnique "claim_id"' in BATCH
    assert 'ColumnValues "claim_amount" >= 0' in BATCH
    assert 'IsComplete "policy_id"' in BATCH
    assert BATCH.index("dq_result = _run_glue_dq(valid") < BATCH.index('_write_iceberg(latest, args["SILVER_DATABASE"], "claim"')
    assert '"enableDataQualityResultsPublishing": True' in BATCH
    assert '"data_quality"' in BATCH
    assert "input_count=valid_count + rejected_count" in BATCH
    assert "rejected_count=rejected_count" in BATCH


def test_cdc_dqdl_covers_only_present_transaction_entities():
    for entity in ("claims", "policies", "customers", "payments"):
        assert f'"{entity}":' in CDC
    assert '"products":' not in CDC.split("DQDL_RULES =", 1)[1].split("}", 1)[0]
    assert 'dq_result = _run_glue_dq(current, args, table)' in CDC
    assert 'raise DQGateFailure(f"Glue Data Quality gate failed' in CDC
    assert CDC.index('dq_result = _run_glue_dq(current, args, table)') < CDC.index('# No trusted-layer writes occur until every applicable dataset gate passes.')
    assert CDC.index('# No trusted-layer writes occur until every applicable dataset gate passes.') < CDC.index('write_iceberg(current, args["SILVER_DATABASE"], table')


def test_iam_can_publish_and_read_glue_dq_results_without_scheduling_jobs():
    for module in (ROOT / "terraform/modules/batch-ingestion/main.tf", ROOT / "terraform/modules/cdc/main.tf"):
        text = module.read_text(encoding="utf-8")
        assert 'glue:PublishDataQuality' in text
        assert 'glue:GetDataQualityResult' in text
        assert 'dataQualityRuleset/*' in text
