output "state_bucket_name" {
  description = "Name of the DEV S3 bucket that will hold Terraform state."
  value       = module.state_backend.bucket_name
}

output "state_kms_key_arn" {
  description = "ARN of the DEV customer-managed KMS key for Terraform state."
  value       = module.state_backend.kms_key_arn
}

output "state_kms_key_alias" {
  description = "Alias of the DEV customer-managed KMS key for Terraform state."
  value       = module.state_backend.kms_key_alias
}

output "backend_state_keys" {
  description = "Approved bootstrap and foundation state object keys."
  value       = module.state_backend.backend_state_keys
}

output "local_operator_user_name" {
  description = "Console-only IAM user; Terraform creates no password or access key."
  value       = module.dev_operator.user_name
}

output "local_operator_user_arn" {
  description = "ARN of the console-only local development user."
  value       = module.dev_operator.user_arn
}

output "operator_role_arn" {
  description = "MFA-protected V3 operator role managed by bootstrap state."
  value       = module.dev_operator.operator_role_arn
}

output "terraform_execution_role_arn" {
  description = "Bootstrap-managed role used for the first and subsequent foundation plans/applies."
  value       = module.dev_operator.terraform_execution_role_arn
}
