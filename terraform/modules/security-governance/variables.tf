variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "account_id" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" { type = string }
variable "operator_trusted_principal_arns" {
  description = "Existing non-root same-account console-only user or federated role principals allowed to assume the operator role."
  type        = list(string)
  validation {
    condition = length(var.operator_trusted_principal_arns) > 0 && alltrue([
      for arn in var.operator_trusted_principal_arns :
      can(regex("^arn:aws:iam::${var.account_id}:(role|user)/.+$", arn)) && arn != "arn:aws:iam::${var.account_id}:root"
    ])
    error_message = "Provide at least one explicit existing non-root same-account IAM user or role ARN; root is not accepted."
  }
}
variable "bucket_arns" { type = map(string) }
variable "state_bucket_arn" { type = string }
variable "platform_kms_key_arn" { type = string }
variable "audit_kms_key_arn" { type = string }
variable "state_kms_key_arn" { type = string }
variable "rds_secret_arn" { type = string }
variable "glue_database_names" { type = map(string) }
variable "batch_glue_job_names" { type = map(string) }
variable "cdc_glue_job_names" { type = map(string) }
variable "batch_state_machine_arn" { type = string }
variable "cdc_state_machine_arn" { type = string }
variable "athena_workgroup_name" { type = string }
variable "sagemaker_execution_role_arn" { type = string }
variable "rag_knowledge_base_id" { type = string }
variable "rag_vector_bucket_arn" { type = string }
variable "rag_vector_index_arn" { type = string }
variable "rag_generation_model_arns" { type = list(string) }
variable "tags" { type = map(string) }
