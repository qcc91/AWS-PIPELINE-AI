module "state_backend" {
  source = "../../modules/state-backend"

  environment               = "dev"
  org_short                 = var.org_short
  account_short             = var.account_short
  account_id                = var.account_id
  terraform_role_arns       = var.terraform_role_arns
  kms_admin_role_arns       = var.kms_admin_role_arns
  allow_root_for_v1         = true
  noncurrent_retention_days = var.noncurrent_retention_days
  create_resources          = true
}
