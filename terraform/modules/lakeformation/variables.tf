variable "environment" {
  description = "Environment represented by the Lake Formation configuration."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "account_id" {
  description = "Target account used to validate every IAM principal."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "lakehouse_location_arn" {
  description = "Explicit S3 ARN registered for the lakehouse location."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/[^*]+)?$", var.lakehouse_location_arn))
    error_message = "lakehouse_location_arn must be an explicit non-wildcard S3 ARN."
  }
}

variable "control_location_arn" {
  description = "Explicit distinct S3 ARN registered for the control location."
  type        = string

  validation {
    condition = (
      can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/[^*]+)?$", var.control_location_arn)) &&
      var.control_location_arn != var.lakehouse_location_arn
    )
    error_message = "control_location_arn must be an explicit non-wildcard S3 ARN different from lakehouse_location_arn."
  }
}

variable "data_access_role_arn" {
  description = "Explicit same-account IAM role used for both registered locations."
  type        = string

  validation {
    condition = (
      can(regex(
        "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
        var.data_access_role_arn,
      ))
    )
    error_message = "data_access_role_arn must be an explicit same-account role ARN with no wildcard."
  }
}

variable "admin_role_arns" {
  description = "Non-empty list of explicit same-account Lake Formation administrator roles."
  type        = list(string)

  validation {
    condition = (
      length(var.admin_role_arns) > 0 &&
      length(distinct(var.admin_role_arns)) == length(var.admin_role_arns) &&
      alltrue([
        for arn in var.admin_role_arns : can(regex(
          "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
          arn,
        ))
      ])
    )
    error_message = "admin_role_arns must contain unique explicit same-account role ARNs."
  }
}

variable "data_engineer_role_arn" {
  description = "Explicit same-account DataEngineer role ARN."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.data_engineer_role_arn))
    error_message = "data_engineer_role_arn must be an explicit same-account role ARN."
  }
}

variable "analyst_role_arn" {
  description = "Explicit same-account Analyst role ARN."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.analyst_role_arn))
    error_message = "analyst_role_arn must be an explicit same-account role ARN."
  }
}

variable "ml_engineer_role_arn" {
  description = "Explicit same-account MLEngineer role ARN."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.ml_engineer_role_arn))
    error_message = "ml_engineer_role_arn must be an explicit same-account role ARN."
  }
}

variable "rag_application_role_arn" {
  description = "Explicit same-account RAGApplication role ARN; validated but never granted permissions here."
  type        = string

  validation {
    condition = (
      can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.rag_application_role_arn)) &&
      length(distinct(concat(
        var.admin_role_arns,
        [
          var.data_access_role_arn,
          var.data_engineer_role_arn,
          var.analyst_role_arn,
          var.ml_engineer_role_arn,
          var.rag_application_role_arn,
        ],
      ))) == length(var.admin_role_arns) + 5
    )
    error_message = "All Lake Formation admin, access, DataEngineer, Analyst, MLEngineer, and RAGApplication roles must be distinct explicit same-account roles."
  }
}

variable "database_names" {
  description = "Exact Glue database names keyed by bronze, silver, gold, and control."
  type        = map(string)

  validation {
    condition = (
      length(var.database_names) == 4 && alltrue([
        for layer in ["bronze", "silver", "gold", "control"] :
        lookup(var.database_names, layer, "") == "insurance_${var.environment}_${layer}"
      ])
    )
    error_message = "database_names must contain exactly the four environment-specific bronze, silver, gold, and control names."
  }
}

variable "tags" {
  description = "Complete project tag contract retained for integration because Lake Formation grant resources are not taggable."
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
    error_message = "tags must contain the complete non-empty project contract and approved environment/classification values."
  }
}

variable "analyst_gold_tables" {
  description = "Explicit non-PII Gold tables approved for Analyst SELECT."
  type        = set(string)
}

variable "ml_gold_tables" {
  description = "Explicit Gold feature/output tables approved for MLEngineer SELECT."
  type        = set(string)
}

variable "pipeline_role_arns" {
  description = "Existing Glue/DMS execution roles requiring DATA_LOCATION_ACCESS after registration."
  type        = set(string)
}
