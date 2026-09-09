variable "environment" {
  type        = string
  description = "DEV or PROD environment."
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "aws_region" {
  type = string
}

variable "account_id" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit account ID."
  }
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnets are required for RDS and DMS."
  }
}

variable "landing_bucket_name" {
  type = string
}
variable "lakehouse_bucket_name" {
  type = string
}
variable "control_bucket_name" {
  type = string
}
variable "kms_key_arn" {
  type = string
}

variable "glue_database_names" {
  type = map(string)
  validation {
    condition     = alltrue([for layer in ["bronze", "silver", "gold"] : contains(keys(var.glue_database_names), layer)])
    error_message = "glue_database_names must include bronze, silver, and gold."
  }
}

variable "cdc_script_path" {
  type        = string
  description = "Local Glue CDC script uploaded as a versioned artifact."
}

variable "seed_script_path" {
  type        = string
  description = "Local Glue SQL bootstrap/mutation script uploaded as an artifact."
}

variable "schema_sql_path" {
  type        = string
  description = "Local PostgreSQL schema SQL uploaded as a controlled artifact."
}

variable "seed_sql_path" {
  type        = string
  description = "Local synthetic seed SQL uploaded as a controlled artifact."
}

variable "mutation_sql_path" {
  type        = string
  description = "Local synthetic INSERT/UPDATE/DELETE SQL uploaded as a controlled artifact."
}

variable "database_name" {
  type    = string
  default = "insurance"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{1,62}$", var.database_name))
    error_message = "database_name must be a lowercase PostgreSQL identifier."
  }
}

variable "master_username" {
  type    = string
  default = "insurance_admin"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,30}$", var.master_username))
    error_message = "master_username must be a lowercase PostgreSQL identifier."
  }
}

variable "rds_engine_version" {
  type    = string
  default = "16.15"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "dms_instance_class" {
  type    = string
  default = "dms.t3.small"
}

variable "tags" {
  type        = map(string)
  description = "Complete project tag contract."
}
