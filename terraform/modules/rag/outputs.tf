output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID."
  value       = aws_bedrockagent_knowledge_base.this.id
}
output "data_source_id" {
  description = "Approved-document data source ID."
  value       = aws_bedrockagent_data_source.this.data_source_id
}
output "vector_bucket_arn" {
  description = "S3 Vectors bucket ARN."
  value       = aws_s3vectors_vector_bucket.this.vector_bucket_arn
}
output "vector_index_arn" {
  description = "S3 Vectors index ARN."
  value       = aws_s3vectors_index.this.index_arn
}
output "bedrock_role_arn" {
  description = "Knowledge Base service role ARN."
  value       = aws_iam_role.bedrock.arn
}
