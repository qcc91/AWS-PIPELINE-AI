output "environment" {
  description = "Environment represented by this foundation root."
  value       = local.environment
}

output "deployment_enabled" {
  description = "Whether the complete DEV foundation topology is enabled."
  value       = var.enable_deployment
}

output "expected_resource_instance_count" {
  description = "Approved static DEV foundation instance count checked against reviewed plan JSON."
  value       = 62
}

output "monthly_budget_review_threshold_usd" {
  description = "Human cost-review threshold supplied for this plan; no AWS Budgets resource is created."
  value       = var.monthly_budget_usd
}

output "common_tags" {
  description = "Canonical tags applied across the DEV foundation."
  value       = module.common.tags
}

output "vpc_id" {
  description = "ID of the DEV private VPC."
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the two DEV private subnets."
  value       = module.networking.private_subnet_ids
}

output "s3_gateway_endpoint_id" {
  description = "ID of the DEV S3 Gateway endpoint."
  value       = module.networking.s3_gateway_endpoint_id
}

output "platform_kms_key_arn" {
  description = "ARN of the DEV platform data KMS key."
  value       = module.platform_kms.key_arn
}

output "storage_bucket_arns" {
  description = "ARNs of the five purpose-separated DEV data buckets."
  value = {
    for purpose, bucket in module.storage : purpose => bucket.bucket_arn
  }
}

output "storage_bucket_ids" {
  description = "Names of the five purpose-separated DEV data buckets."
  value = {
    for purpose, bucket in module.storage : purpose => bucket.bucket_id
  }
}

output "terraform_execution_role_arn" {
  description = "V3 non-root Terraform execution role ARN."
  value       = try(module.security_governance[0].role_arns["TerraformExecution"], null)
}

output "lakeformation_registration_role_arn" {
  description = "V3 Lake Formation registration role ARN."
  value       = try(module.security_governance[0].role_arns["LakeFormationRegistration"], null)
}

output "glue_database_names" {
  description = "Names of the bronze, silver, gold, and control Glue databases."
  value       = module.glue.database_names
}

output "lakeformation_registered_location_arns" {
  description = "V3 registered Lake Formation locations."
  value       = try(module.lakeformation[0].registered_location_arns, [])
}

output "lakeformation_database_permission_matrix" {
  description = "V3 Lake Formation database permissions."
  value       = try(module.lakeformation[0].database_metadata_permission_matrix, {})
}

output "v3_security_role_arns" {
  description = "V3 non-secret role ARNs for operator/persona access testing."
  value       = try(module.security_governance[0].role_arns, {})
}

output "lakeformation_table_permission_matrix" {
  description = "V3 governed table SELECT matrix."
  value       = try(module.lakeformation[0].table_select_permission_matrix, {})
}

output "audit_kms_key_arn" {
  description = "ARN of the dedicated DEV audit KMS key."
  value       = module.monitoring.audit_kms_key_arn
}

output "audit_bucket_arn" {
  description = "ARN of the DEV CloudTrail audit bucket."
  value       = module.monitoring.audit_bucket_arn
}

output "cloudtrail_arn" {
  description = "ARN of the DEV management-events CloudTrail trail."
  value       = module.monitoring.cloudtrail_arn
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the DEV encrypted CloudTrail log group."
  value       = module.monitoring.log_group_arn
}

output "sns_topic_arn" {
  description = "ARN of the DEV encrypted alert topic with no subscriptions."
  value       = module.monitoring.sns_topic_arn
}

output "batch_glue_job_name" {
  description = "V2 Batch Bronze Glue job (legacy V1 name retained for an in-place migration)."
  value       = module.batch_ingestion.glue_job_name
}

output "batch_glue_job_names" {
  description = "V2 Batch Glue jobs by Medallion stage."
  value       = module.batch_ingestion.glue_job_names
}

output "batch_state_machine_arn" {
  description = "V1 broker claim CSV Step Functions state machine."
  value       = module.batch_ingestion.state_machine_arn
}

output "batch_event_rule_arn" {
  description = "V1 broker claim CSV EventBridge rule."
  value       = module.batch_ingestion.event_rule_arn
}

output "cdc_rds_endpoint" {
  description = "Private V1 CDC PostgreSQL endpoint."
  value       = module.cdc.rds_endpoint
}

output "cdc_dms_task_id" {
  description = "V1 DMS full-load-and-CDC task identifier."
  value       = module.cdc.dms_task_id
}

output "cdc_dms_task_arn" {
  description = "V1 DMS full-load-and-CDC task ARN used by operational commands."
  value       = module.cdc.dms_task_arn
}

output "cdc_seed_job_name" {
  description = "Glue VPC job used to initialize/mutate the private RDS source."
  value       = module.cdc.seed_job_name
}

output "cdc_glue_job_name" {
  description = "V2 CDC Bronze Glue job (legacy V1 name retained for an in-place migration)."
  value       = module.cdc.cdc_job_name
}

output "cdc_glue_job_names" {
  description = "V2 CDC Glue jobs by Medallion stage."
  value       = module.cdc.cdc_job_names
}

output "cdc_state_machine_arn" {
  description = "V1 CDC Step Functions state machine."
  value       = module.cdc.cdc_state_machine_arn
}

output "bi_athena_workgroup_name" {
  value       = module.bi.athena_workgroup_name
  description = "V1 BI Athena workgroup with enforced encrypted results."
}

output "bi_named_query_ids" {
  description = "V1 BI Athena named-query IDs for the two Gold contracts."
  value = {
    fact_claim          = module.bi.fact_claim_named_query_id
    claim_daily_summary = module.bi.claim_daily_summary_named_query_id
  }
}

output "bi_quicksight_enabled" {
  value       = module.bi.quicksight_enabled
  description = "Whether optional QuickSight resources are enabled."
}

output "ml_sagemaker_role_arn" {
  description = "V1 on-demand SageMaker training and Batch Transform role."
  value       = module.ml.sagemaker_role_arn
}

output "ml_model_package_group_name" {
  description = "V1 claim-fraud model registry group."
  value       = module.ml.model_package_group_name
}

output "rag_knowledge_base_id" {
  description = "V1 Bedrock Knowledge Base ID."
  value       = module.rag.knowledge_base_id
}

output "rag_data_source_id" {
  description = "V1 approved-document data source ID."
  value       = module.rag.data_source_id
}

output "rag_vector_index_arn" {
  description = "V1 S3 Vectors index ARN."
  value       = module.rag.vector_index_arn
}
