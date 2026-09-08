variable "environment" {
  description = "Environment embedded in Glue database names."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "lakehouse_location_uri" {
  description = "S3 base URI below which bronze, silver, and gold locations are derived."
  type        = string

  validation {
    condition     = can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/[^*]+/?$", var.lakehouse_location_uri))
    error_message = "lakehouse_location_uri must be a non-wildcard S3 prefix URI."
  }
}

variable "control_location_uri" {
  description = "Dedicated S3 prefix URI for control metadata."
  type        = string

  validation {
    condition = (
      can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/[^*]+/?$", var.control_location_uri)) &&
      !contains([
        trimsuffix(var.lakehouse_location_uri, "/"),
        "${trimsuffix(var.lakehouse_location_uri, "/")}/bronze",
        "${trimsuffix(var.lakehouse_location_uri, "/")}/silver",
        "${trimsuffix(var.lakehouse_location_uri, "/")}/gold",
      ], trimsuffix(var.control_location_uri, "/"))
    )
    error_message = "control_location_uri must be a non-wildcard S3 prefix distinct from the lakehouse base and all derived layer locations."
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
    error_message = "tags must contain the complete non-empty project contract and approved environment/classification values."
  }
}
