variable "environment" {
  type = string
}
variable "aws_region" {
  type = string
}
variable "account_id" {
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
variable "gold_database_name" {
  type = string
}
variable "tags" {
  type = map(string)
}

variable "xgboost_version" {
  description = "Version passed to SageMaker SDK image_uris.retrieve; never a hand-written URI."
  type        = string
  default     = "1.7-1"
}
variable "pipeline_script_path" {
  type = string
}
variable "training_data_path" {
  type = string
}
variable "postprocess_script_path" {
  type = string
}
