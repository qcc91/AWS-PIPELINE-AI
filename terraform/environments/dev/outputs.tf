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
  value       = 76
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
  description = "ARN of the DEV Terraform execution role."
  value       = module.iam.terraform_execution_role_arn
}

output "lakeformation_registration_role_arn" {
  description = "ARN of the DEV Lake Formation registration role."
  value       = module.iam.lakeformation_registration_role_arn
}

output "glue_database_names" {
  description = "Names of the bronze, silver, gold, and control Glue databases."
  value       = module.glue.database_names
}

output "lakeformation_registered_location_arns" {
  description = "ARNs of the registered lakehouse and control locations."
  value       = module.lakeformation.registered_location_arns
}

output "lakeformation_database_permission_matrix" {
  description = "Database metadata permission matrix, including the explicit RAG zero-grant boundary."
  value       = module.lakeformation.database_metadata_permission_matrix
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
