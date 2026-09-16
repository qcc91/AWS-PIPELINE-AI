variable "environment" {
  description = "Environment represented by the monitoring resources."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "account_id" {
  description = "Target account used in CloudTrail, KMS, S3, Logs, and SNS conditions."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "bucket_name" {
  description = "Globally unique dedicated audit bucket name."
  type        = string

  validation {
    condition = (
      length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "..") &&
      !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.bucket_name))
    )
    error_message = "bucket_name must be a valid lowercase non-IP S3 bucket name without adjacent periods."
  }
}

variable "kms_admin_role_arns" {
  description = "At least one explicit same-account administrator for the dedicated audit KMS key."
  type        = list(string)
  default     = []

  validation {
    condition = (
      (var.allow_root_for_v1 || length(var.kms_admin_role_arns) > 0) && alltrue([
        for arn in var.kms_admin_role_arns : can(regex(
          "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
          arn,
        ))
      ])
    )
    error_message = "kms_admin_role_arns must contain explicit same-account path-capable role ARNs without wildcards."
  }
}
variable "allow_root_for_v1" {
  description = "Explicit V1 temporary root admin allowance."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Explicit CloudWatch Logs retention selected from AWS-supported values."
  type        = number

  validation {
    condition = (
      contains([
        30,
        60,
        90,
        120,
        150,
        180,
        365,
        400,
        545,
        731,
        1096,
        1827,
        2192,
        2557,
        2922,
        3288,
        3653,
      ], var.log_retention_days)
    )
    error_message = "log_retention_days must be an AWS-supported value from 30 through 3653 days."
  }
}

variable "audit_noncurrent_retention_days" {
  description = "Human-approved noncurrent audit-object retention with no default."
  type        = number

  validation {
    condition = (
      var.audit_noncurrent_retention_days >= 30 &&
      var.audit_noncurrent_retention_days <= 3650 &&
      floor(var.audit_noncurrent_retention_days) == var.audit_noncurrent_retention_days
    )
    error_message = "audit_noncurrent_retention_days must be an integer between 30 and 3650."
  }
}

variable "audit_retention_days" {
  description = "Human-approved current audit-object retention with no default."
  type        = number

  validation {
    condition = (
      var.audit_retention_days >= 30 &&
      var.audit_retention_days <= 3650 &&
      floor(var.audit_retention_days) == var.audit_retention_days &&
      var.audit_retention_days >= var.audit_noncurrent_retention_days
    )
    error_message = "audit_retention_days must be an integer from 30 to 3650 and at least audit_noncurrent_retention_days."
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

variable "enable_operational_alerting" {
  description = "Enable the focused V5 operational alert set. Kept false for the intentionally minimal PROD design."
  type        = bool
  default     = false
}

variable "workflow_state_machine_arns" {
  description = "Approved Step Functions state machines keyed by concise pipeline name."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for name, arn in var.workflow_state_machine_arns :
      contains(["batch", "cdc"], name) && can(regex("^arn:aws:states:ap-southeast-2:${var.account_id}:stateMachine:insurance-${var.environment}-[A-Za-z0-9_-]+$", arn))
    ])
    error_message = "workflow_state_machine_arns may contain only approved batch/cdc state machine ARNs in ap-southeast-2."
  }
}

variable "glue_job_names" {
  description = "Exact existing Glue job names whose terminal failures route to SNS."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for name in var.glue_job_names : can(regex("^insurance-${var.environment}-[A-Za-z0-9_-]+$", name))])
    error_message = "glue_job_names must contain only environment-scoped insurance Glue job names."
  }
}

variable "dms_replication_task_id" {
  description = "Exact existing DMS replication task identifier used for failure events."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.dms_replication_task_id == null || var.dms_replication_task_id == "insurance${var.environment}cdc" || can(regex("^insurance-${var.environment}-[A-Za-z0-9-]+$", var.dms_replication_task_id))
    error_message = "dms_replication_task_id must be null or the environment-scoped insurance task ID."
  }
}

variable "codepipeline_name" {
  description = "Existing V4 CodePipeline name; null disables the CI/CD pipeline alarm."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.codepipeline_name == null || var.codepipeline_name == "insurance-dev-v4b-cd"
    error_message = "codepipeline_name may reference only the accepted V4B pipeline."
  }
}

variable "codebuild_project_names" {
  description = "Existing V4B CodeBuild projects keyed by CloudWatch-safe metric query IDs."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for id, name in var.codebuild_project_names :
      can(regex("^[a-z][a-z0-9_]*$", id)) && can(regex("^insurance-dev-v4b-[A-Za-z0-9-]+$", name))
    ])
    error_message = "codebuild_project_names keys must be valid metric IDs and values must be accepted V4B project names."
  }
}
