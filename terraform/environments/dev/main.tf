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

data "aws_kms_alias" "terraform_state" {
  name = "alias/insurance/${local.environment}/terraform-state"
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
  admin_role_arns   = length(var.v3_operator_trusted_principal_arns) > 0 ? [module.security_governance[0].role_arns["TerraformExecution"]] : var.kms_admin_role_arns
  allow_root_for_v1 = length(var.v3_operator_trusted_principal_arns) == 0
  user_role_arns = length(var.v3_operator_trusted_principal_arns) > 0 ? [
    module.security_governance[0].role_arns["DataEngineer"], module.security_governance[0].role_arns["Analyst"],
    module.security_governance[0].role_arns["MLEngineer"], module.security_governance[0].role_arns["RAGApplication"],
    module.security_governance[0].role_arns["LakeFormationRegistration"], module.batch_ingestion.glue_role_arn,
    module.cdc.glue_role_arn, module.cdc.dms_s3_role_arn, module.cdc.dms_secrets_role_arn,
    module.ml.sagemaker_role_arn, module.ml.postprocess_role_arn, module.rag.bedrock_role_arn,
  ] : []
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

  environment            = local.environment
  aws_region             = var.aws_region
  account_id             = var.account_id
  landing_bucket_name    = module.storage["landing"].bucket_id
  lakehouse_bucket_name  = module.storage["lakehouse"].bucket_id
  control_bucket_name    = module.storage["control"].bucket_id
  quarantine_bucket_name = module.storage["quarantine"].bucket_id
  kms_key_arn            = module.platform_kms.key_arn
  glue_database_names    = module.glue.database_names
  glue_script_path       = abspath("${path.root}/../../../jobs/glue_claim_pipeline.py")
  # One prefix intentionally covers the original broker claims file and the
  # V1 file-based master/reference datasets under batch/reference/.
  batch_key_prefix = "batch/"
  tags             = module.common.tags
}

module "cdc" {
  source = "../../modules/cdc"

  environment            = local.environment
  aws_region             = var.aws_region
  account_id             = var.account_id
  vpc_id                 = module.networking.vpc_id
  private_subnet_ids     = module.networking.private_subnet_ids
  landing_bucket_name    = module.storage["landing"].bucket_id
  lakehouse_bucket_name  = module.storage["lakehouse"].bucket_id
  control_bucket_name    = module.storage["control"].bucket_id
  quarantine_bucket_name = module.storage["quarantine"].bucket_id
  kms_key_arn            = module.platform_kms.key_arn
  glue_database_names    = module.glue.database_names
  cdc_script_path        = abspath("${path.root}/../../../jobs/glue_cdc_pipeline.py")
  seed_script_path       = abspath("${path.root}/../../../jobs/glue_cdc_sql_bootstrap.py")
  schema_sql_path        = abspath("${path.root}/../../../sql/cdc/001_schema.sql")
  seed_sql_path          = abspath("${path.root}/../../../sql/cdc/002_seed.sql")
  mutation_sql_path      = abspath("${path.root}/../../../sql/cdc/003_mutations.sql")
  tags                   = module.common.tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  environment                     = local.environment
  account_id                      = var.account_id
  bucket_name                     = "${var.org_short}-insurance-${local.environment}-audit-logs-${var.account_short}"
  kms_admin_role_arns             = length(var.v3_operator_trusted_principal_arns) > 0 ? [module.security_governance[0].role_arns["TerraformExecution"]] : var.kms_admin_role_arns
  allow_root_for_v1               = length(var.v3_operator_trusted_principal_arns) == 0
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

module "security_governance" {
  source = "../../modules/security-governance"
  count  = length(var.v3_operator_trusted_principal_arns) > 0 ? 1 : 0

  environment                     = local.environment
  account_id                      = var.account_id
  aws_region                      = var.aws_region
  operator_trusted_principal_arns = var.v3_operator_trusted_principal_arns
  bucket_arns                     = { for purpose, bucket in module.storage : purpose => bucket.bucket_arn }
  state_bucket_arn                = "arn:aws:s3:::${var.org_short}-insurance-${local.environment}-tfstate-${var.account_short}"
  platform_kms_key_arn            = module.platform_kms.key_arn
  audit_kms_key_arn               = module.monitoring.audit_kms_key_arn
  state_kms_key_arn               = data.aws_kms_alias.terraform_state.target_key_arn
  rds_secret_arn                  = module.cdc.rds_secret_arn
  glue_database_names             = module.glue.database_names
  batch_glue_job_names            = module.batch_ingestion.glue_job_names
  cdc_glue_job_names              = module.cdc.cdc_job_names
  batch_state_machine_arn         = module.batch_ingestion.state_machine_arn
  cdc_state_machine_arn           = module.cdc.cdc_state_machine_arn
  athena_workgroup_name           = module.bi.athena_workgroup_name
  sagemaker_execution_role_arn    = module.ml.sagemaker_role_arn
  rag_knowledge_base_id           = module.rag.knowledge_base_id
  rag_vector_bucket_arn           = module.rag.vector_bucket_arn
  rag_vector_index_arn            = module.rag.vector_index_arn
  rag_generation_model_arns = [
    "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-micro-v1:0",
  ]
  tags = module.common.tags
}

module "lakeformation" {
  source = "../../modules/lakeformation"
  count  = length(var.v3_operator_trusted_principal_arns) > 0 ? 1 : 0

  environment              = local.environment
  account_id               = var.account_id
  lakehouse_location_arn   = "${module.storage["lakehouse"].bucket_arn}/lakehouse"
  control_location_arn     = "${module.storage["control"].bucket_arn}/control"
  data_access_role_arn     = module.security_governance[0].role_arns["LakeFormationRegistration"]
  admin_role_arns          = [module.security_governance[0].role_arns["TerraformExecution"]]
  data_engineer_role_arn   = module.security_governance[0].role_arns["DataEngineer"]
  analyst_role_arn         = module.security_governance[0].role_arns["Analyst"]
  ml_engineer_role_arn     = module.security_governance[0].role_arns["MLEngineer"]
  rag_application_role_arn = module.security_governance[0].role_arns["RAGApplication"]
  database_names           = module.glue.database_names
  analyst_gold_tables      = toset(["broker_performance", "claim_daily_summary", "claim_daily_summary_cdc", "dim_branch", "dim_broker", "dim_claim_type", "dim_coverage", "dim_product_master", "dim_region_risk", "dim_vehicle", "policy_performance"])
  ml_gold_tables           = toset(["claim_risk_features", "claim_risk"])
  pipeline_role_arns       = toset([module.batch_ingestion.glue_role_arn, module.cdc.glue_role_arn, module.ml.postprocess_role_arn])
  tags                     = module.common.tags
}
