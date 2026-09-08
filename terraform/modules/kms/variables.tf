variable "environment" {
  description = "Environment represented by the key and its alias."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "purpose" {
  description = "Non-empty lowercase purpose used in the key description, alias, and Purpose tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.purpose))
    error_message = "purpose must be 2-63 lowercase alphanumeric or hyphen characters and start/end alphanumeric."
  }
}

variable "account_id" {
  description = "Target account ID used to scope every KMS policy principal."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "admin_role_arns" {
  description = "At least one explicit same-account KMS administrator role ARN; role paths are supported."
  type        = list(string)

  validation {
    condition = length(var.admin_role_arns) > 0 && alltrue([
      for arn in var.admin_role_arns : can(regex(
        "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
        arn,
      ))
    ])
    error_message = "admin_role_arns must contain at least one explicit same-account IAM role ARN without wildcards."
  }
}

variable "user_role_arns" {
  description = "Explicit same-account KMS data-plane user role ARNs; an empty list is allowed."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.user_role_arns : can(regex(
        "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
        arn,
      ))
    ])
    error_message = "user_role_arns must contain only explicit same-account IAM role ARNs without wildcards."
  }
}

variable "tags" {
  description = "Complete project tag contract; no defaults are supplied."
  type        = map(string)

  validation {
    condition = alltrue([
      for key in [
        "Project",
        "Environment",
        "Owner",
        "ManagedBy",
        "CostCenter",
        "DataClassification",
      ] : trimspace(lookup(var.tags, key, "")) != ""
      ]) && lookup(var.tags, "ManagedBy", "") == "terraform" &&
      lookup(var.tags, "Environment", "") == var.environment &&
      contains(
        ["public", "internal", "confidential", "restricted"],
        lookup(var.tags, "DataClassification", ""),
      )
    error_message = "tags must include non-empty Project, Environment, Owner, ManagedBy, CostCenter, and DataClassification; Environment must match, ManagedBy must be terraform, and classification must be approved."
  }
}
