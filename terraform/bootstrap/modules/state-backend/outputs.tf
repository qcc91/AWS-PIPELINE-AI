output "bucket_name" {
  description = "Actual or planned environment-specific Terraform state bucket name."
  value       = var.create_resources ? aws_s3_bucket.state[0].bucket : local.bucket_name
}

output "kms_key_arn" {
  description = "Actual state KMS key ARN, or an empty string when resource creation is disabled."
  value       = var.create_resources ? aws_kms_key.state[0].arn : ""
}

output "kms_key_alias" {
  description = "Environment-specific alias for the Terraform state KMS key."
  value       = local.key_alias
}

output "backend_state_keys" {
  description = "Approved isolated object keys for bootstrap and foundation state."
  value = [
    "bootstrap/terraform.tfstate",
    "foundation/terraform.tfstate",
  ]
}
