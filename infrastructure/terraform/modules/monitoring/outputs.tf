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

output "operational_alarm_arns" {
  description = "Focused V5 CloudWatch alarm ARNs keyed by operational signal."
  value = merge(
    { for key, alarm in aws_cloudwatch_metric_alarm.workflow_failures : "${key}_workflow" => alarm.arn },
    length(aws_cloudwatch_metric_alarm.codepipeline_failures) > 0 ? { codepipeline = aws_cloudwatch_metric_alarm.codepipeline_failures[0].arn } : {},
    length(aws_cloudwatch_metric_alarm.codebuild_failures) > 0 ? { codebuild = aws_cloudwatch_metric_alarm.codebuild_failures[0].arn } : {},
  )
}

output "glue_failure_rule_arn" {
  description = "EventBridge rule ARN for approved Glue terminal failure events."
  value       = try(aws_cloudwatch_event_rule.glue_job_failures[0].arn, null)
}

output "dms_failure_subscription_name" {
  description = "DMS event subscription scoped to the approved replication task."
  value       = try(aws_dms_event_subscription.task_failures[0].name, null)
}
