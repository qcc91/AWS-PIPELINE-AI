variable "aws_region" {
  description = "Reserved for later modules; this design is pinned to Sydney."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "Only ap-southeast-2 is approved for this project."
  }
}
