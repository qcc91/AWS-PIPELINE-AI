variable "environment" {
  description = "Deployment environment; intentionally explicit rather than a Terraform workspace."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "owner" {
  description = "Owning team or service (never a person name)."
  type        = string
  default     = "platform"
}

variable "cost_center" {
  description = "Approved cost allocation identifier."
  type        = string
  default     = "insurance-data-ai"
}

variable "data_classification" {
  description = "Highest classification held by the component."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential, or restricted."
  }
}
