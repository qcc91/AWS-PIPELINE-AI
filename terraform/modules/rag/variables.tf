variable "environment" {
  description = "Environment name."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "aws_region" {
  description = "Approved Bedrock/S3 Vectors region."
  type        = string
  default     = "ap-southeast-2"
  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "RAG is approved only in ap-southeast-2; do not silently use another region."
  }
}

variable "documents_bucket_arn" {
  description = "Existing governed S3 documents bucket ARN."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.documents_bucket_arn))
    error_message = "documents_bucket_arn must be an S3 bucket ARN."
  }
}

variable "documents_prefix" {
  type    = string
  default = "rag/approved/"
}
variable "kms_key_arn" {
  description = "KMS key used by the governed documents bucket."
  type        = string
}
variable "embedding_model_arn" {
  description = "Discovered, approved Sydney embedding model ARN; never infer this value."
  type        = string
}
variable "embedding_dimensions" {
  description = "Dimension supported by embedding_model_arn and the S3 Vector index."
  type        = number
  default     = 1024
  validation {
    condition     = var.embedding_dimensions > 0 && floor(var.embedding_dimensions) == var.embedding_dimensions
    error_message = "embedding_dimensions must be a positive integer discovered for the selected model."
  }
}
variable "vector_bucket_name" {
  description = "Globally unique S3 Vectors bucket name."
  type        = string
}
variable "vector_index_name" {
  type    = string
  default = "insurance-rag-index"
}
variable "knowledge_base_name" {
  type    = string
  default = "insurance-rag"
}
variable "tags" {
  type = map(string)
}
