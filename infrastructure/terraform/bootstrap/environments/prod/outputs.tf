output "design_state_bucket_name" {
  description = "Planned name of the separate PROD state bucket; no bucket is created."
  value       = module.state_backend.bucket_name
}

output "design_state_kms_key_arn" {
  description = "Empty until a separately approved PROD bootstrap creates its KMS key."
  value       = module.state_backend.kms_key_arn
}

output "design_state_kms_key_alias" {
  description = "Planned alias of the separate PROD state KMS key."
  value       = module.state_backend.kms_key_alias
}

output "design_backend_state_keys" {
  description = "Approved PROD bootstrap and foundation state object keys."
  value       = module.state_backend.backend_state_keys
}
