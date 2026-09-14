variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "source_revision" {
  type = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.source_revision)) || var.source_revision == "local-validation"
    error_message = "source_revision must be a Git commit SHA or local-validation."
  }
}

variable "pipeline_execution_id" {
  type = string
}
