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
variable "operator_role_arn" {
  description = "Existing bootstrap-managed Operator role ARN."
  type        = string
  nullable    = true
  validation {
    condition     = var.operator_role_arn == null || var.operator_role_arn == "arn:aws:iam::${var.account_id}:role/insurance-${var.environment}-operator-role"
    error_message = "operator_role_arn must be the exact bootstrap-managed environment role."
  }
}
variable "terraform_execution_role_arn" {
  description = "Existing bootstrap-managed Terraform execution role ARN."
  type        = string
  nullable    = true
  validation {
    condition     = var.terraform_execution_role_arn == null || var.terraform_execution_role_arn == "arn:aws:iam::${var.account_id}:role/insurance-${var.environment}-terraform-execution-role"
    error_message = "terraform_execution_role_arn must be the exact bootstrap-managed environment role."
  }
}
variable "bucket_arns" { type = map(string) }
variable "platform_kms_key_arn" { type = string }
variable "rds_secret_arn" { type = string }
variable "glue_database_names" { type = map(string) }
variable "batch_glue_job_names" { type = map(string) }
variable "cdc_glue_job_names" { type = map(string) }
variable "batch_state_machine_arn" { type = string }
variable "cdc_state_machine_arn" { type = string }
variable "athena_workgroup_name" { type = string }
variable "sagemaker_execution_role_arn" { type = string }
variable "rag_knowledge_base_id" { type = string }
variable "rag_generation_model_arns" { type = list(string) }
variable "tags" { type = map(string) }
