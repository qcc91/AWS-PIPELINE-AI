output "audit_kms_key_arn" {
  description = "ARN of the dedicated audit encryption KMS key."
  value       = aws_kms_key.audit.arn
}

output "audit_bucket_arn" {
  description = "ARN of the private versioned CloudTrail audit bucket."
  value       = aws_s3_bucket.audit.arn
}

output "log_group_arn" {
  description = "ARN of the encrypted retained CloudWatch log group."
  value       = aws_cloudwatch_log_group.audit.arn
}

output "cloudtrail_arn" {
  description = "ARN of the management-events-only regional CloudTrail trail."
  value       = aws_cloudtrail.management.arn
}

output "sns_topic_arn" {
  description = "ARN of the encrypted alert topic; no subscription is created."
  value       = aws_sns_topic.alerts.arn
}
