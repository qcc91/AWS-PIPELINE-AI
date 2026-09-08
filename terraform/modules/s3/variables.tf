variable "bucket_name" {
  description = "Globally unique lowercase S3 bucket name."
  type        = string

  validation {
    condition = length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "..") &&
      !strcontains(var.bucket_name, ".-") &&
      !strcontains(var.bucket_name, "-.") &&
      !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|\\.mrap|--x-s3|--table-s3)$", var.bucket_name))
    error_message = "bucket_name must satisfy S3 naming rules and must not use reserved prefixes/suffixes, adjacent periods, dot-hyphen pairs, or IP-address format."
  }
}

variable "kms_key_arn" {
  description = "Actual ap-southeast-2 customer-managed KMS key ARN, not an alias ARN."
  type        = string

  validation {
    condition = can(regex(
      "^arn:aws:kms:ap-southeast-2:[0-9]{12}:key/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
      var.kms_key_arn,
    ))
    error_message = "kms_key_arn must be an actual ap-southeast-2 KMS key ARN with a UUID key ID."
  }
}

variable "purpose" {
  description = "Approved non-empty bucket purpose, also written to the Purpose tag."
  type        = string

  validation {
    condition = contains([
      "landing",
      "lakehouse",
      "control",
      "quarantine",
      "documents",
      "artifacts",
      "audit-logs",
    ], var.purpose)
    error_message = "purpose must be an approved non-empty bucket purpose."
  }
}

variable "noncurrent_retention_days" {
  description = "Human-approved noncurrent object-version retention; no default is supplied."
  type        = number

  validation {
    condition = var.noncurrent_retention_days >= 7 &&
      var.noncurrent_retention_days <= 3650 &&
      floor(var.noncurrent_retention_days) == var.noncurrent_retention_days
    error_message = "noncurrent_retention_days must be an integer between 7 and 3650."
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
      contains(["dev", "prod"], lookup(var.tags, "Environment", "")) &&
      contains(
        ["public", "internal", "confidential", "restricted"],
        lookup(var.tags, "DataClassification", ""),
      )
    error_message = "tags must include non-empty Project, Environment, Owner, ManagedBy, CostCenter, and DataClassification; ManagedBy must be terraform and values must be approved."
  }
}
