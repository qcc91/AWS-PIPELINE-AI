variable "environment" {
  description = "Environment represented by the IAM roles."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "account_id" {
  description = "Target AWS account ID used to scope IAM principals and ARNs."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "trusted_role_arns" {
  description = "Explicit same-account IAM roles allowed to assume the Terraform execution role."
  type        = list(string)

  validation {
    condition = (
      length(var.trusted_role_arns) > 0 && alltrue([
        for arn in var.trusted_role_arns : can(regex(
          "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
          arn,
        ))
      ])
    )
    error_message = "trusted_role_arns must contain explicit same-account role ARNs with no wildcard principals."
  }
}

variable "data_location_bucket_arns" {
  description = "Exactly two explicit S3 bucket ARNs for lakehouse and control data locations."
  type        = list(string)

  validation {
    condition = (
      length(var.data_location_bucket_arns) == 2 &&
      length(distinct(var.data_location_bucket_arns)) == 2 &&
      alltrue([
        for arn in var.data_location_bucket_arns : can(regex(
          "^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$",
          arn,
        ))
      ])
    )
    error_message = "data_location_bucket_arns must contain two distinct explicit S3 bucket ARNs."
  }
}

variable "data_kms_key_arns" {
  description = "One or more explicit Sydney KMS key ARNs used by the two data locations."
  type        = list(string)

  validation {
    condition = (
      length(var.data_kms_key_arns) > 0 && alltrue([
        for arn in var.data_kms_key_arns : can(regex(
          "^arn:aws:kms:ap-southeast-2:${var.account_id}:key/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
          arn,
        ))
      ])
    )
    error_message = "data_kms_key_arns must contain explicit same-account ap-southeast-2 key ARNs."
  }
}

variable "tags" {
  description = "Complete project tag contract with no defaults."
  type        = map(string)

  validation {
    condition = (
      alltrue([
        for key in ["Project", "Environment", "Owner", "ManagedBy", "CostCenter", "DataClassification"] :
        trimspace(lookup(var.tags, key, "")) != ""
      ]) && lookup(var.tags, "Environment", "") == var.environment &&
      lookup(var.tags, "ManagedBy", "") == "terraform" &&
      contains(["public", "internal", "confidential", "restricted"], lookup(var.tags, "DataClassification", ""))
    )
    error_message = "tags must contain the complete non-empty project contract, match environment, use ManagedBy=terraform, and use an approved classification."
  }
}
