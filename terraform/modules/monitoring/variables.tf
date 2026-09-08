variable "environment" {
  description = "Environment represented by the monitoring resources."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "account_id" {
  description = "Target account used in CloudTrail, KMS, S3, Logs, and SNS conditions."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "bucket_name" {
  description = "Globally unique dedicated audit bucket name."
  type        = string

  validation {
    condition = length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "..") &&
      !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.bucket_name))
    error_message = "bucket_name must be a valid lowercase non-IP S3 bucket name without adjacent periods."
  }
}

variable "kms_admin_role_arns" {
  description = "At least one explicit same-account administrator for the dedicated audit KMS key."
  type        = list(string)

  validation {
    condition = length(var.kms_admin_role_arns) > 0 && alltrue([
      for arn in var.kms_admin_role_arns : can(regex(
        "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
        arn,
      ))
    ])
    error_message = "kms_admin_role_arns must contain explicit same-account path-capable role ARNs without wildcards."
  }
}

variable "log_retention_days" {
  description = "Explicit CloudWatch Logs retention selected from AWS-supported values."
  type        = number

  validation {
    condition = contains([
      30,
      60,
      90,
      120,
      150,
      180,
      365,
      400,
      545,
      731,
      1096,
      1827,
      2192,
      2557,
      2922,
      3288,
      3653,
    ], var.log_retention_days)
    error_message = "log_retention_days must be an AWS-supported value from 30 through 3653 days."
  }
}

variable "audit_noncurrent_retention_days" {
  description = "Human-approved noncurrent audit-object retention with no default."
  type        = number

  validation {
    condition = var.audit_noncurrent_retention_days >= 30 &&
      var.audit_noncurrent_retention_days <= 3650 &&
      floor(var.audit_noncurrent_retention_days) == var.audit_noncurrent_retention_days
    error_message = "audit_noncurrent_retention_days must be an integer between 30 and 3650."
  }
}

variable "audit_retention_days" {
  description = "Human-approved current audit-object retention with no default."
  type        = number

  validation {
    condition = var.audit_retention_days >= 30 &&
      var.audit_retention_days <= 3650 &&
      floor(var.audit_retention_days) == var.audit_retention_days &&
      var.audit_retention_days >= var.audit_noncurrent_retention_days
    error_message = "audit_retention_days must be an integer from 30 to 3650 and at least audit_noncurrent_retention_days."
  }
}

variable "tags" {
  description = "Complete project tag contract with no defaults."
  type        = map(string)

  validation {
    condition = alltrue([
      for key in ["Project", "Environment", "Owner", "ManagedBy", "CostCenter", "DataClassification"] :
      trimspace(lookup(var.tags, key, "")) != ""
      ]) && lookup(var.tags, "Environment", "") == var.environment &&
      lookup(var.tags, "ManagedBy", "") == "terraform" &&
      contains(["public", "internal", "confidential", "restricted"], lookup(var.tags, "DataClassification", ""))
    error_message = "tags must contain the complete non-empty project contract and approved environment/classification values."
  }
}
