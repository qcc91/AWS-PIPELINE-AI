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

variable "pipeline_prepare_script_path" {
  description = "Local SageMaker Processing entry point that validates and splits Gold feature exports."
  type        = string
}

variable "pipeline_evaluate_script_path" {
  description = "Local SageMaker Processing entry point that evaluates the untouched test split."
  type        = string
}

variable "pipeline_publish_script_path" {
  description = "Local SageMaker Processing entry point that publishes and validates Gold predictions."
  type        = string
}

variable "claim_risk_library_path" {
  description = "Local leakage-safe feature and metric library used by SageMaker Processing steps."
  type        = string
}

variable "athena_workgroup_name" {
  description = "Existing encrypted Athena workgroup used for Gold feature export and final validation."
  type        = string
}

variable "unified_studio_project_id" {
  description = "Existing SageMaker Unified Studio/DataZone project ID used for native project resource discovery."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{4,35}$", var.unified_studio_project_id))
    error_message = "unified_studio_project_id must be a valid DataZone project identifier."
  }
}

variable "processing_image_uri" {
  description = "AWS-published scikit-learn processing image used by prepare and publication steps."
  type        = string
  default     = "783357654285.dkr.ecr.ap-southeast-2.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"

  validation {
    condition     = startswith(var.processing_image_uri, "783357654285.dkr.ecr.ap-southeast-2.amazonaws.com/sagemaker-scikit-learn:")
    error_message = "processing_image_uri must use the AWS-published SageMaker scikit-learn repository in ap-southeast-2."
  }
}

variable "xgboost_image_uri" {
  description = "AWS-published SageMaker XGBoost image used for training, evaluation, and batch inference."
  type        = string
  default     = "783357654285.dkr.ecr.ap-southeast-2.amazonaws.com/sagemaker-xgboost:1.7-1"

  validation {
    condition     = startswith(var.xgboost_image_uri, "783357654285.dkr.ecr.ap-southeast-2.amazonaws.com/sagemaker-xgboost:")
    error_message = "xgboost_image_uri must use the AWS-published SageMaker XGBoost repository in ap-southeast-2."
  }
}
