data "aws_kms_alias" "platform" {
  name = "alias/insurance/dev/platform-data"
}

data "aws_kms_alias" "audit" {
  name = "alias/insurance/dev/audit"
}

module "state_backend" {
  source = "../../modules/state-backend"

  environment               = "dev"
  org_short                 = var.org_short
  account_short             = var.account_short
  account_id                = var.account_id
  terraform_role_arns       = var.terraform_role_arns
  kms_admin_role_arns       = var.kms_admin_role_arns
  allow_root_for_v1         = length(var.terraform_role_arns) == 0
  noncurrent_retention_days = var.noncurrent_retention_days
  create_resources          = true
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
    data.aws_kms_alias.platform.target_key_arn,
    data.aws_kms_alias.audit.target_key_arn,
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
