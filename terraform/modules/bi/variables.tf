variable "environment" {
  type        = string
  description = "Deployment environment suffix."
}

variable "aws_region" {
  type = string
}
variable "account_id" {
  type      = string
  sensitive = true
}
variable "gold_database_name" {
  type = string
}
variable "control_bucket_name" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "enable_quicksight" {
  type        = bool
  default     = false
  description = "Create QuickSight resources only after account subscription and principal inputs are approved."

  validation {
    condition     = !var.enable_quicksight || (var.quicksight_account_id != null && var.quicksight_user_arn != null && var.quicksight_edition != null)
    error_message = "enable_quicksight requires explicit quicksight_account_id, quicksight_user_arn, and quicksight_edition."
  }
}

variable "quicksight_account_id" {
  type        = string
  default     = null
  nullable    = true
  description = "QuickSight account ID; must be explicit when enable_quicksight is true."
}

variable "quicksight_user_arn" {
  type        = string
  default     = null
  nullable    = true
  description = "Approved QuickSight principal ARN for dataset permissions."
}

variable "quicksight_namespace" {
  type        = string
  default     = "default"
  description = "QuickSight namespace."
}

variable "quicksight_data_source_id" {
  type    = string
  default = "insurance-dev-athena"
}

variable "quicksight_edition" {
  type        = string
  default     = null
  nullable    = true
  description = "Documented input only; edition is account-level and not created by this module."
}
