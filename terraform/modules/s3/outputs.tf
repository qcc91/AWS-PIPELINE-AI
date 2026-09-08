output "bucket_arn" {
  description = "ARN of the encrypted private S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "Name and provider ID of the encrypted private S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_purpose" {
  description = "Validated business purpose applied to the Purpose tag."
  value       = var.purpose
}
