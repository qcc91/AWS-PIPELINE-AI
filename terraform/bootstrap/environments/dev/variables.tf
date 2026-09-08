variable "aws_region" {
  description = "AWS Region for the DEV bootstrap; only Sydney is approved."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "Only ap-southeast-2 is approved."
  }
}

variable "org_short" {
  description = "Required organization short identifier; no value is invented."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.org_short))
    error_message = "org_short must be 2-12 lowercase alphanumeric characters."
  }
}

variable "account_short" {
  description = "Required stable account suffix; do not use the full account ID in names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.account_short))
    error_message = "account_short must be 2-12 lowercase alphanumeric characters."
  }
}

variable "account_id" {
  description = "Required 12-digit DEV AWS account ID used to scope the KMS policy."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "terraform_role_arns" {
  description = "At least one approved same-account DEV IAM role ARN; role paths are supported and wildcards are rejected."
  type        = list(string)

  validation {
    condition = length(var.terraform_role_arns) > 0 && alltrue([
      for arn in var.terraform_role_arns : can(regex(
        "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
        arn,
      ))
    ])
    error_message = "Provide at least one explicit same-account Terraform role ARN."
  }
}

variable "noncurrent_retention_days" {
  description = "Human-approved DEV noncurrent state-version retention; no default is supplied."
  type        = number

  validation {
    condition     = var.noncurrent_retention_days >= 7 && var.noncurrent_retention_days <= 3650
    error_message = "noncurrent_retention_days must be between 7 and 3650."
  }
}
