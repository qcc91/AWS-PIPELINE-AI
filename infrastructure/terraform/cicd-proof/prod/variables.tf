variable "aws_region" {
  type    = string
  default = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "V4B is restricted to ap-southeast-2."
  }
}

variable "source_revision" {
  type    = string
  default = "local-validation"
}

variable "pipeline_execution_id" {
  type    = string
  default = "local-validation"
}
