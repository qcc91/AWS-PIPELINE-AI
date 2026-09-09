from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_bi_sql_uses_gold_contract_and_excludes_direct_pii():
    fact = (ROOT / "sql" / "bi" / "fact_claim.sql").read_text(encoding="utf-8").lower()
    summary = (ROOT / "sql" / "bi" / "claim_daily_summary.sql").read_text(encoding="utf-8").lower()
    assert "insurance_dev_gold.fact_claim" in fact
    assert "insurance_dev_gold.claim_daily_summary" in summary
    for text in (fact, summary):
        assert "first_name" not in text
        assert "last_name" not in text
        assert "email" not in text
        assert "description" not in text


def test_quicksight_is_opt_in_and_has_explicit_prerequisite_guard():
    module = (ROOT / "terraform" / "modules" / "bi" / "variables.tf").read_text(encoding="utf-8")
    assert 'default     = false' in module
    assert "quicksight_account_id != null" in module
    assert "quicksight_user_arn != null" in module
    assert "quicksight_edition != null" in module


def test_bi_uses_existing_kms_and_control_bucket():
    main = (ROOT / "terraform" / "modules" / "bi" / "main.tf").read_text(encoding="utf-8")
    assert "var.control_bucket_name" in main
    assert "var.kms_key_arn" in main
    assert "encryption_option = \"SSE_KMS\"" in main
