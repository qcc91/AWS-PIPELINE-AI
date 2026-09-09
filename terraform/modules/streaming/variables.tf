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
variable "glue_database_names" {
  type = map(string)
}
variable "glue_script_path" {
  type = string
}
variable "tags" {
  type = map(string)
}
