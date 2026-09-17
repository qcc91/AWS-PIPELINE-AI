variable "aws_region" {
  type    = string
  default = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "V4B control plane is restricted to ap-southeast-2."
  }
}

variable "account_id" {
  type      = string
  sensitive = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "github_owner" {
  type    = string
  default = "qcc91"
}

variable "github_repository" {
  type    = string
  default = "AWS-PIPELINE-AI"
}

variable "github_connection_arn" {
  description = "Existing AVAILABLE CodeConnections ARN. Null creates a PENDING connection requiring one console handshake."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.github_connection_arn == null || can(regex("^arn:aws:(codeconnections|codestar-connections):ap-southeast-2:[0-9]{12}:connection/[0-9a-f-]+$", var.github_connection_arn))
    error_message = "github_connection_arn must be an explicit Sydney connection ARN."
  }
}

variable "state_bucket_name" {
  description = "Existing V3 state bucket reused with isolated V4B keys."
  type        = string
  default     = "aip-insurance-dev-tfstate-dev01"
}

variable "state_kms_key_arn" {
  description = "Existing V3 Terraform-state KMS key ARN."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:ap-southeast-2:[0-9]{12}:key/[0-9a-f-]+$", var.state_kms_key_arn))
    error_message = "state_kms_key_arn must be the existing Sydney state key ARN."
  }
}
