output "stream_name" {
  description = "V1 insurance-event Kinesis stream name."
  value       = aws_kinesis_stream.events.name
}
output "stream_arn" {
  description = "V1 insurance-event Kinesis stream ARN."
  value       = aws_kinesis_stream.events.arn
}
output "firehose_name" {
  description = "Firehose delivery stream name."
  value       = aws_kinesis_firehose_delivery_stream.events.name
}
output "glue_job_name" {
  description = "Streaming Iceberg Glue job name."
  value       = aws_glue_job.events.name
}
output "producer_policy_arn" {
  description = "Scoped producer IAM policy ARN."
  value       = aws_iam_policy.producer.arn
}
output "state_machine_arn" {
  description = "Streaming Glue state machine ARN."
  value       = aws_sfn_state_machine.events.arn
}
output "event_rule_arn" {
  description = "Firehose-object EventBridge rule ARN."
  value       = aws_cloudwatch_event_rule.lakehouse_stream_object_created.arn
}
