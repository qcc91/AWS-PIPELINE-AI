output "environment" {
  description = "Environment represented by this design-only foundation root."
  value       = local.environment
}

output "deployment_enabled" {
  description = "Whether PROD deployment is enabled; locked false in Phase 1."
  value       = var.enable_deployment
}

output "expected_resource_instance_count" {
  description = "Expected PROD foundation instance count while deployment remains disabled."
  value       = 0
}

output "monthly_budget_review_threshold_usd" {
  description = "Design-only cost-review threshold; PROD remains disabled and no AWS Budgets resource is created."
  value       = var.monthly_budget_usd
}

output "common_tags" {
  description = "Canonical tags for the design-only PROD foundation."
  value       = module.common.tags
}

output "vpc_id" {
  description = "PROD VPC ID when deployment is authorized in a future phase."
  value       = try(module.networking[0].vpc_id, null)
}

output "private_subnet_ids" {
  description = "PROD private subnet IDs when deployment is authorized in a future phase."
  value       = try(module.networking[0].private_subnet_ids, [])
}

output "s3_gateway_endpoint_id" {
  description = "PROD S3 Gateway endpoint ID when deployment is authorized in a future phase."
  value       = try(module.networking[0].s3_gateway_endpoint_id, null)
}

output "platform_kms_key_arn" {
  description = "PROD platform KMS key ARN when deployment is authorized in a future phase."
  value       = try(module.platform_kms[0].key_arn, null)
}

output "storage_bucket_arns" {
  description = "PROD purpose-separated bucket ARNs; empty while deployment is disabled."
  value = {
    for purpose, bucket in module.storage : purpose => bucket.bucket_arn
  }
}

output "storage_bucket_ids" {
  description = "PROD purpose-separated bucket names; empty while deployment is disabled."
  value = {
    for purpose, bucket in module.storage : purpose => bucket.bucket_id
  }
}

output "terraform_execution_role_arn" {
  description = "PROD Terraform execution role ARN when deployment is authorized in a future phase."
  value       = try(module.iam[0].terraform_execution_role_arn, null)
}

output "lakeformation_registration_role_arn" {
  description = "PROD Lake Formation registration role ARN when deployment is authorized in a future phase."
  value       = try(module.iam[0].lakeformation_registration_role_arn, null)
}

output "glue_database_names" {
  description = "PROD Glue database names; empty while deployment is disabled."
  value       = try(module.glue[0].database_names, {})
}

output "lakeformation_registered_location_arns" {
  description = "PROD registered Lake Formation locations; empty while deployment is disabled."
  value       = try(module.lakeformation[0].registered_location_arns, {})
}

output "lakeformation_database_permission_matrix" {
  description = "PROD database metadata permission matrix; empty while deployment is disabled."
  value       = try(module.lakeformation[0].database_metadata_permission_matrix, {})
}

output "audit_kms_key_arn" {
  description = "PROD audit KMS key ARN when deployment is authorized in a future phase."
  value       = try(module.monitoring[0].audit_kms_key_arn, null)
}

output "audit_bucket_arn" {
  description = "PROD audit bucket ARN when deployment is authorized in a future phase."
  value       = try(module.monitoring[0].audit_bucket_arn, null)
}

output "cloudtrail_arn" {
  description = "PROD CloudTrail ARN when deployment is authorized in a future phase."
  value       = try(module.monitoring[0].cloudtrail_arn, null)
}

output "cloudwatch_log_group_arn" {
  description = "PROD CloudWatch log group ARN when deployment is authorized in a future phase."
  value       = try(module.monitoring[0].log_group_arn, null)
}

output "sns_topic_arn" {
  description = "PROD encrypted alert topic ARN when deployment is authorized in a future phase."
  value       = try(module.monitoring[0].sns_topic_arn, null)
}
