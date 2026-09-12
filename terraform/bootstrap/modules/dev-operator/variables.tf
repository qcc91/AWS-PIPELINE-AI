variable "environment" {
  type = string
}

variable "account_id" {
  type      = string
  sensitive = true
}

variable "target_role_arns" {
  description = "Exact TerraformExecution and persona roles the operator may assume."
  type        = set(string)
  validation {
    condition = length(var.target_role_arns) == 5 && alltrue([
      for arn in var.target_role_arns : can(regex("^arn:aws:iam::${var.account_id}:role/insurance-${var.environment}-(terraform-execution|data-engineer|analyst|ml-engineer|rag-application)-role$", arn))
    ])
    error_message = "target_role_arns must be the five exact DEV Terraform/persona role ARNs."
  }
}

variable "tags" {
  type = map(string)
}

variable "state_bucket_arn" { type = string }
variable "state_kms_key_arn" { type = string }
variable "platform_kms_key_arns" { type = set(string) }
