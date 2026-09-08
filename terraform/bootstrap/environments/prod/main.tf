module "state_backend" {
  source = "../../modules/state-backend"

  environment               = "prod"
  org_short                 = var.org_short
  account_short             = var.account_short
  account_id                = var.account_id
  terraform_role_arns       = var.terraform_role_arns
  noncurrent_retention_days = var.noncurrent_retention_days
  create_resources          = false
}
