data "aws_secretsmanager_secret" "rds" {
  name = "insurance-dev-cdc-postgres"
}

module "state_backend" {
  source = "../../modules/state-backend"

  environment                        = "dev"
  org_short                          = var.org_short
  account_short                      = var.account_short
  account_id                         = var.account_id
  terraform_role_arns                = var.terraform_role_arns
  kms_admin_role_arns                = var.kms_admin_role_arns
  allow_account_root_bootstrap_admin = true
  noncurrent_retention_days          = var.noncurrent_retention_days
  create_resources                   = true
  future_terraform_role_arns = [
    "arn:aws:iam::${var.account_id}:role/insurance-dev-v4b-proof-dev-role",
    "arn:aws:iam::${var.account_id}:role/insurance-dev-v4b-proof-prod-plan-role",
    "arn:aws:iam::${var.account_id}:role/insurance-dev-v4b-proof-prod-apply-role",
  ]
}

module "dev_operator" {
  source = "../../modules/dev-operator"

  environment = "dev"
  account_id  = var.account_id
  target_role_arns = toset([
    "arn:aws:iam::${var.account_id}:role/insurance-dev-terraform-execution-role",
    "arn:aws:iam::${var.account_id}:role/insurance-dev-data-engineer-role",
    "arn:aws:iam::${var.account_id}:role/insurance-dev-analyst-role",
    "arn:aws:iam::${var.account_id}:role/insurance-dev-ml-engineer-role",
    "arn:aws:iam::${var.account_id}:role/insurance-dev-rag-application-role",
  ])
  state_bucket_arn  = "arn:aws:s3:::${module.state_backend.bucket_name}"
  state_kms_key_arn = module.state_backend.kms_key_arn
  platform_kms_key_arns = toset([
    var.platform_kms_key_arn,
    var.audit_kms_key_arn,
  ])
  rds_secret_arn = data.aws_secretsmanager_secret.rds.arn
  project_bucket_arns = toset([
    for purpose in ["landing", "lakehouse", "control", "quarantine", "documents", "audit-logs"] :
    "arn:aws:s3:::${var.org_short}-insurance-dev-${purpose}-${var.account_short}"
  ])
  tags = {
    Project            = "aws-insurance-data-ai-platform"
    Environment        = "dev"
    Owner              = "platform"
    ManagedBy          = "terraform"
    CostCenter         = "insurance-data-ai"
    DataClassification = "restricted"
  }
}
