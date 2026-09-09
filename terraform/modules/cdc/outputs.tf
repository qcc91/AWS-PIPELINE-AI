output "rds_endpoint" {
  description = "Private PostgreSQL endpoint address."
  value       = aws_db_instance.source.address
}
output "rds_secret_arn" {
  description = "KMS-encrypted DMS-compatible PostgreSQL secret ARN."
  value       = aws_secretsmanager_secret.source.arn
  sensitive   = true
}
output "dms_task_arn" {
  description = "DMS full-load-and-CDC task ARN."
  value       = aws_dms_replication_task.source.replication_task_arn
}
output "dms_task_id" {
  description = "DMS full-load-and-CDC task ID."
  value       = aws_dms_replication_task.source.replication_task_id
}
output "seed_job_name" {
  description = "Private PostgreSQL schema/seed/mutation Glue job name."
  value       = aws_glue_job.seed.name
}
output "cdc_job_name" {
  description = "CDC Iceberg materialization Glue job name."
  value       = aws_glue_job.cdc.name
}
output "cdc_state_machine_arn" {
  description = "CDC Glue orchestration state machine ARN."
  value       = aws_sfn_state_machine.cdc.arn
}
output "cdc_event_rule_arn" {
  description = "DMS S3 object EventBridge rule ARN."
  value       = aws_cloudwatch_event_rule.cdc_object_created.arn
}
