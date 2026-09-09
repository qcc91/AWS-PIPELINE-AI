locals {
  environment = "dev"
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
  source = "../../modules/networking"

  name                   = "insurance-${local.environment}"
  vpc_cidr               = var.vpc_cidr
  private_subnet_newbits = var.private_subnet_newbits
  private_subnet_netnums = var.private_subnet_netnums
  availability_zones     = var.availability_zones
  tags                   = module.common.tags
}

module "platform_kms" {
  source = "../../modules/kms"

  environment       = local.environment
  purpose           = "platform-data"
  account_id        = var.account_id
  admin_role_arns   = var.kms_admin_role_arns
  allow_root_for_v1 = var.allow_root_for_v1
  user_role_arns    = []
  s3vectors_bucket_arns = [
    "arn:aws:s3vectors:${var.aws_region}:${var.account_id}:bucket/${var.org_short}-insurance-${local.environment}-vectors-${var.account_short}",
  ]
  tags = module.common.tags
}

module "storage" {
  source   = "../../modules/s3"
  for_each = local.bucket_names

  bucket_name               = each.value
  kms_key_arn               = module.platform_kms.key_arn
  purpose                   = each.key
  noncurrent_retention_days = var.data_noncurrent_retention_days
  current_retention_days    = each.key == "quarantine" ? 90 : null
  tags                      = module.common.tags
}

module "glue" {
  source = "../../modules/glue"

  environment            = local.environment
  lakehouse_location_uri = "s3://${module.storage["lakehouse"].bucket_id}/lakehouse"
  control_location_uri   = "s3://${module.storage["control"].bucket_id}/control"
  tags                   = module.common.tags
}

module "batch_ingestion" {
  source = "../../modules/batch-ingestion"

  environment           = local.environment
  aws_region            = var.aws_region
  account_id            = var.account_id
  landing_bucket_name   = module.storage["landing"].bucket_id
  lakehouse_bucket_name = module.storage["lakehouse"].bucket_id
  control_bucket_name   = module.storage["control"].bucket_id
  kms_key_arn           = module.platform_kms.key_arn
  glue_database_names   = module.glue.database_names
  glue_script_path      = abspath("${path.root}/../../../jobs/glue_claim_pipeline.py")
  tags                  = module.common.tags
}

module "cdc" {
  source = "../../modules/cdc"

  environment           = local.environment
  aws_region            = var.aws_region
  account_id            = var.account_id
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  landing_bucket_name   = module.storage["landing"].bucket_id
  lakehouse_bucket_name = module.storage["lakehouse"].bucket_id
  control_bucket_name   = module.storage["control"].bucket_id
  kms_key_arn           = module.platform_kms.key_arn
  glue_database_names   = module.glue.database_names
  cdc_script_path       = abspath("${path.root}/../../../jobs/glue_cdc_pipeline.py")
  seed_script_path      = abspath("${path.root}/../../../jobs/glue_cdc_sql_bootstrap.py")
  schema_sql_path       = abspath("${path.root}/../../../sql/cdc/001_schema.sql")
  seed_sql_path         = abspath("${path.root}/../../../sql/cdc/002_seed.sql")
  mutation_sql_path     = abspath("${path.root}/../../../sql/cdc/003_mutations.sql")
  tags                  = module.common.tags
}

module "streaming" {
  source = "../../modules/streaming"

  environment           = local.environment
  aws_region            = var.aws_region
  account_id            = var.account_id
  lakehouse_bucket_name = module.storage["lakehouse"].bucket_id
  control_bucket_name   = module.storage["control"].bucket_id
  kms_key_arn           = module.platform_kms.key_arn
  glue_database_names   = module.glue.database_names
  glue_script_path      = abspath("${path.root}/../../../jobs/glue_streaming_pipeline.py")
  tags                  = module.common.tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  environment                     = local.environment
  account_id                      = var.account_id
  bucket_name                     = "${var.org_short}-insurance-${local.environment}-audit-logs-${var.account_short}"
  kms_admin_role_arns             = var.kms_admin_role_arns
  allow_root_for_v1               = var.allow_root_for_v1
  log_retention_days              = var.log_retention_days
  audit_noncurrent_retention_days = var.audit_noncurrent_retention_days
  audit_retention_days            = var.audit_retention_days
  tags                            = module.common.tags
}

module "bi" {
  source = "../../modules/bi"

  environment         = local.environment
  aws_region          = var.aws_region
  account_id          = var.account_id
  gold_database_name  = module.glue.database_names["gold"]
  control_bucket_name = module.storage["control"].bucket_id
  kms_key_arn         = module.platform_kms.key_arn
  tags                = module.common.tags
  # QuickSight is account/subscription scoped. Enable only after the explicit
  # account ID, edition, and approved principal ARN are supplied.
  enable_quicksight     = var.enable_quicksight
  quicksight_account_id = var.quicksight_account_id
  quicksight_user_arn   = var.quicksight_user_arn
  quicksight_namespace  = var.quicksight_namespace
  quicksight_edition    = var.quicksight_edition
}

module "ml" {
  source = "../../modules/ml"

  environment             = local.environment
  aws_region              = var.aws_region
  account_id              = var.account_id
  lakehouse_bucket_name   = module.storage["lakehouse"].bucket_id
  control_bucket_name     = module.storage["control"].bucket_id
  kms_key_arn             = module.platform_kms.key_arn
  gold_database_name      = module.glue.database_names["gold"]
  pipeline_script_path    = abspath("${path.root}/../../../jobs/ml_claim_fraud_pipeline.py")
  training_data_path      = abspath("${path.root}/../../../data/sample/ml_claim_training.csv")
  postprocess_script_path = abspath("${path.root}/../../../jobs/glue_claim_risk_postprocess.py")
  tags                    = module.common.tags
}

module "rag" {
  source = "../../modules/rag"

  environment          = local.environment
  aws_region           = var.aws_region
  documents_bucket_arn = module.storage["documents"].bucket_arn
  kms_key_arn          = module.platform_kms.key_arn

  # Manager-discovered in ap-southeast-2 on 2026-09-09.
  embedding_model_arn  = "arn:aws:bedrock:ap-southeast-2::foundation-model/amazon.titan-embed-text-v2:0"
  embedding_dimensions = 1024
  vector_bucket_name   = "${var.org_short}-insurance-${local.environment}-vectors-${var.account_short}"
  vector_index_name    = "insurance-rag-index"
  knowledge_base_name  = "insurance-${local.environment}-rag"
  tags                 = module.common.tags
}
