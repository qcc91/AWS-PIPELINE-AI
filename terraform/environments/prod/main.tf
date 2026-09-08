locals {
  environment = "prod"
  bucket_names = {
    for purpose in [
      "landing",
      "lakehouse",
      "control",
      "quarantine",
      "documents",
    ] : purpose => "${var.org_short}-insurance-${local.environment}-${purpose}-${var.account_short}"
  }
}

module "common" {
  source = "../../modules/common"

  environment         = local.environment
  owner               = var.owner
  cost_center         = var.cost_center
  data_classification = var.data_classification
}

module "networking" {
  count  = var.enable_deployment ? 1 : 0
  source = "../../modules/networking"

  name                   = "insurance-${local.environment}"
  vpc_cidr               = var.vpc_cidr
  private_subnet_newbits = var.private_subnet_newbits
  private_subnet_netnums = var.private_subnet_netnums
  availability_zones     = var.availability_zones
  tags                   = module.common.tags
}

module "platform_kms" {
  count  = var.enable_deployment ? 1 : 0
  source = "../../modules/kms"

  environment     = local.environment
  purpose         = "platform-data"
  account_id      = var.account_id
  admin_role_arns = var.kms_admin_role_arns
  user_role_arns  = []
  tags            = module.common.tags
}

module "storage" {
  source   = "../../modules/s3"
  for_each = var.enable_deployment ? local.bucket_names : {}

  bucket_name               = each.value
  kms_key_arn               = module.platform_kms[0].key_arn
  purpose                   = each.key
  noncurrent_retention_days = var.data_noncurrent_retention_days
  tags                      = module.common.tags
}

module "iam" {
  count  = var.enable_deployment ? 1 : 0
  source = "../../modules/iam"

  environment       = local.environment
  account_id        = var.account_id
  trusted_role_arns = var.terraform_trusted_role_arns
  data_location_bucket_arns = [
    module.storage["lakehouse"].bucket_arn,
    module.storage["control"].bucket_arn,
  ]
  data_kms_key_arns = [module.platform_kms[0].key_arn]
  tags              = module.common.tags
}

module "glue" {
  count  = var.enable_deployment ? 1 : 0
  source = "../../modules/glue"

  environment            = local.environment
  lakehouse_location_uri = "s3://${module.storage["lakehouse"].bucket_id}/lakehouse"
  control_location_uri   = "s3://${module.storage["control"].bucket_id}/control"
  tags                   = module.common.tags
}

module "lakeformation" {
  count  = var.enable_deployment ? 1 : 0
  source = "../../modules/lakeformation"

  environment              = local.environment
  account_id               = var.account_id
  lakehouse_location_arn   = "${module.storage["lakehouse"].bucket_arn}/lakehouse"
  control_location_arn     = "${module.storage["control"].bucket_arn}/control"
  data_access_role_arn     = module.iam[0].lakeformation_registration_role_arn
  admin_role_arns          = var.lakeformation_admin_role_arns
  data_engineer_role_arn   = var.data_engineer_role_arn
  analyst_role_arn         = var.analyst_role_arn
  ml_engineer_role_arn     = var.ml_engineer_role_arn
  rag_application_role_arn = var.rag_application_role_arn
  database_names           = module.glue[0].database_names
  tags                     = module.common.tags
}

module "monitoring" {
  count  = var.enable_deployment ? 1 : 0
  source = "../../modules/monitoring"

  environment                     = local.environment
  account_id                      = var.account_id
  bucket_name                     = "${var.org_short}-insurance-${local.environment}-audit-logs-${var.account_short}"
  kms_admin_role_arns             = var.kms_admin_role_arns
  log_retention_days              = var.log_retention_days
  audit_noncurrent_retention_days = var.audit_noncurrent_retention_days
  audit_retention_days            = var.audit_retention_days
  tags                            = module.common.tags
}
