from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEV = (ROOT / "terraform/environments/dev/main.tf").read_text(encoding="utf-8")
KMS = (ROOT / "terraform/modules/kms/main.tf").read_text(encoding="utf-8")
CDC = (ROOT / "terraform/modules/cdc/main.tf").read_text(encoding="utf-8")


def test_s3_vectors_kms_policy_is_scoped_to_the_real_bucket():
    assert "${var.org_short}-insurance-${local.environment}-vectors-${var.account_short}" in DEV
    assert 'Service = "indexing.s3vectors.amazonaws.com"' in KMS
    assert 'Action    = ["kms:Decrypt"]' in KMS
    assert '"aws:SourceAccount" = var.account_id' in KMS
    assert '"aws:SourceArn" = "${bucket_arn}/*"' in KMS
    assert '"kms:EncryptionContextKeys"' in KMS
    assert '"aws:s3vectors:arn"' in KMS
    assert '"aws:s3vectors:resource-id"' in KMS


def test_secrets_endpoint_policy_is_resource_scoped():
    assert 'Principal = "*"' in CDC
    assert "Resource  = aws_secretsmanager_secret.source.arn" in CDC
    assert '"secretsmanager:GetSecretValue"' in CDC
