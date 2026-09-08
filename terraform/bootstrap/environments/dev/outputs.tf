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
