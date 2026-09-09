from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "terraform/modules/cdc/main.tf").read_text(encoding="utf-8")
JOB = (ROOT / "jobs/glue_cdc_pipeline.py").read_text(encoding="utf-8")
SEED = (ROOT / "jobs/glue_cdc_sql_bootstrap.py").read_text(encoding="utf-8")
SCHEMA = (ROOT / "sql/cdc/001_schema.sql").read_text(encoding="utf-8")
MUTATIONS = (ROOT / "sql/cdc/003_mutations.sql").read_text(encoding="utf-8")


def test_dms_postgres_full_load_cdc_and_s3_mapping():
    assert 'migration_type           = "full-load-and-cdc"' in MODULE
    assert re.search(r'engine_name\s*=\s*"postgres"', MODULE)
    assert re.search(r'plugin_name\s*=\s*"test-decoding"', MODULE)
    assert re.search(r'slot_name\s*=\s*"insurance_\$\{var.environment\}_cdc_slot"', MODULE)
    assert 'resource "aws_dms_endpoint" "postgres_auto"' in MODULE
    assert "source_endpoint_arn      = aws_dms_endpoint.postgres_auto.endpoint_arn" in MODULE
    assert 'name = "claims"' in MODULE or '"table-name" = table_name' in MODULE
    for table in ("customers", "policies", "products", "claims", "payments"):
        assert table in MODULE
    assert re.search(r'data_format\s*=\s*"csv"', MODULE)
    assert "include_op_for_full_load" in MODULE
    assert "cdc_inserts_only" in MODULE
    assert re.search(r"cdc_inserts_and_updates\s*=\s*false", MODULE)
    assert 'resource "aws_dms_s3_endpoint" "s3"' in MODULE
    assert 'bucket_folder                     = local.dms_prefix' in MODULE
    for action in ("s3:DeleteObject", "s3:PutObject", "s3:PutObjectTagging"):
        assert action in MODULE
    assert 'for rule_index, table_name in' in MODULE
    assert '"rule-id" = tostring(rule_index + 1)' in MODULE


def test_private_network_and_secret_references_are_declared():
    assert re.search(r'publicly_accessible\s*=\s*false', MODULE)
    assert "aws_dms_replication_subnet_group" in MODULE
    assert "physical_connection_requirements" in MODULE
    assert "aws_secretsmanager_secret.source.arn" in MODULE
    assert 'resource "aws_vpc_endpoint" "secrets_manager"' in MODULE
    assert 'service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"' in MODULE
    assert 'self        = true' in MODULE
    assert "random_password.source.result" in MODULE
    assert "manage_master_user_password" not in MODULE
    assert "RDS_SECRET_ARN" in SEED
    assert "RDS_JDBC_URL" in SEED
    assert "pg_create_logical_replication_slot" in SEED
    assert '"--SLOT_NAME"' in MODULE
    assert "?sslmode=require" in MODULE
    assert 'Action = ["glue:GetConnection"], Resource = [local.glue_catalog_arn, local.glue_connection_arn]' in MODULE
    assert 'Action = ["ec2:CreateTags", "ec2:DeleteTags"]' in MODULE
    assert '"aws:TagKeys" = ["aws-glue-service-resource"]' in MODULE
    for forbidden in ("access_key", "secret_key"):
        assert forbidden not in MODULE.lower()


def test_cdc_glue_is_iceberg_and_current_state_handles_deletes():
    assert '.using("iceberg")' in JOB
    assert "S3FileIO" in JOB
    assert 'F.col("_operation") != "D"' in JOB
    assert "Window.partitionBy" in JOB
    assert "fact_claim_cdc" in JOB
    assert "claim_daily_summary_cdc" in JOB
    assert '"--CDC_OBJECT_KEY"                   = "manual"' in MODULE
    assert '"--RUN_ID"                           = "manual"' in MODULE


def test_sql_has_all_tables_and_mutation_types():
    for table in ("customers", "products", "policies", "claims", "payments"):
        assert f"CREATE TABLE IF NOT EXISTS {table}" in SCHEMA
    for statement in ("INSERT INTO", "UPDATE claims", "DELETE FROM payments"):
        assert statement in MUTATIONS
