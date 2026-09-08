output "glue_job_name" {
  description = "V1 batch Glue job name."
  value       = aws_glue_job.batch.name
}

output "glue_job_arn" {
  description = "V1 batch Glue job ARN."
  value       = aws_glue_job.batch.arn
}

output "state_machine_name" {
  description = "V1 batch Step Functions state machine name."
  value       = aws_sfn_state_machine.batch.name
}

output "state_machine_arn" {
  description = "V1 batch Step Functions state machine ARN."
  value       = aws_sfn_state_machine.batch.arn
}

output "event_rule_arn" {
  description = "S3 Object Created EventBridge rule ARN."
  value       = aws_cloudwatch_event_rule.landing_object_created.arn
}

output "glue_role_arn" {
  description = "Least-privilege V1 Glue execution role ARN."
  value       = aws_iam_role.glue.arn
}
