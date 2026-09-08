variable "environment" {
  description = "Deployment environment for isolated state resources."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "org_short" {
  description = "Non-sensitive organization short identifier; supplied before bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.org_short))
    error_message = "org_short must be 2-12 lowercase alphanumeric characters."
  }
}

variable "account_short" {
  description = "Non-sensitive stable account suffix; do not use a full account ID in names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.account_short))
    error_message = "account_short must be 2-12 lowercase alphanumeric characters."
  }
}

variable "account_id" {
  description = "Target account ID used only to scope the KMS account-root delegation."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "terraform_role_arns" {
  description = "Explicit approved same-account role ARNs allowed to use the state key; role paths are supported and wildcards are rejected."
  type        = list(string)

  validation {
    condition = (
      length(var.terraform_role_arns) > 0 && alltrue([
        for arn in var.terraform_role_arns : can(regex(
          "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
          arn,
        ))
      ])
    )
    error_message = "terraform_role_arns must contain at least one explicit same-account IAM role ARN."
  }
}
variable "kms_admin_role_arns" {
  description = "Explicit same-account non-root administrators for the state key."
  type        = list(string)
  validation {
    condition     = length(var.kms_admin_role_arns) > 0 && alltrue([for arn in var.kms_admin_role_arns : can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", arn))])
    error_message = "At least one explicit same-account KMS admin role is required."
  }
}

variable "noncurrent_retention_days" {
  description = "Approved retention for noncurrent state versions; must be supplied before apply."
  type        = number

  validation {
    condition     = var.noncurrent_retention_days >= 7 && var.noncurrent_retention_days <= 3650
    error_message = "noncurrent_retention_days must be 7-3650; choose and approve before apply."
  }
}

variable "create_resources" {
  description = "PROD design root defaults false; enable only after separate approval."
  type        = bool
  default     = true
}
