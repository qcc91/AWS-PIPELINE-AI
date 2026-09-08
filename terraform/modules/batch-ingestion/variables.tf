variable "environment" {
  description = "Environment represented by this batch pipeline."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "aws_region" {
  description = "AWS region used in scoped Glue and Step Functions ARNs."
  type        = string
}

variable "account_id" {
  description = "AWS account ID used to scope Glue catalog permissions."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "landing_bucket_name" {
  description = "Existing S3 landing bucket containing broker CSV files."
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "Existing S3 bucket for Bronze, Silver, and Gold Iceberg data."
  type        = string
}

variable "control_bucket_name" {
  description = "Existing S3 bucket for job artifacts and control data."
  type        = string
}

variable "kms_key_arn" {
  description = "Existing platform KMS key used by S3 data and job artifacts."
  type        = string
}


variable "glue_database_names" {
  description = "Existing Glue Catalog database names for each Iceberg layer."
  type        = map(string)

  validation {
    condition     = alltrue([for layer in ["bronze", "silver", "gold"] : contains(keys(var.glue_database_names), layer) && trimspace(var.glue_database_names[layer]) != ""])
    error_message = "glue_database_names must provide non-empty bronze, silver, and gold entries."
  }
}

variable "glue_script_path" {
  description = "Local Glue Spark script uploaded as a versioned job artifact."
  type        = string
}

variable "glue_version" {
  description = "Glue runtime version. Glue 5.0 includes native Iceberg support."
  type        = string
  default     = "5.0"
}

variable "glue_worker_type" {
  description = "Smallest Glue worker type suitable for the V1 demo."
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "On-demand worker count for the short-running V1 job."
  type        = number
  default     = 2

  validation {
    condition     = var.glue_number_of_workers >= 2 && var.glue_number_of_workers <= 10
    error_message = "glue_number_of_workers must be between 2 and 10."
  }
}

variable "batch_key_prefix" {
  description = "Landing prefix watched for completed broker CSV objects."
  type        = string
  default     = "batch/"

  validation {
    condition     = startswith(var.batch_key_prefix, "batch/") && !startswith(var.batch_key_prefix, "/")
    error_message = "batch_key_prefix must be a relative prefix beginning with batch/."
  }
}

variable "tags" {
  description = "Complete project tag contract."
  type        = map(string)
}
