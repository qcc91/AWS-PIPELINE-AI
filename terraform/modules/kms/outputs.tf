output "key_arn" {
  description = "ARN of the customer-managed KMS key."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "ID of the customer-managed KMS key."
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "Environment-specific alias of the customer-managed KMS key."
  value       = aws_kms_alias.this.name
}
