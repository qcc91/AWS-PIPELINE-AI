variable "aws_region" {
  description = "AWS region locked to the approved Sydney region."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "Only ap-southeast-2 is approved for this project."
  }
}

variable "enable_deployment" {
  description = "DEV foundation deployment switch; TASK-INF-005 requires the complete topology."
  type        = bool
  default     = true

  validation {
    condition     = var.enable_deployment
    error_message = "DEV foundation must remain enabled as one complete topology."
  }
}

variable "account_id" {
  description = "Twelve-digit target AWS account ID used only for ARN construction and validation."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "account_short" {
  description = "Non-sensitive lowercase account discriminator used in globally unique bucket names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,10}[a-z0-9]$", var.account_short))
    error_message = "account_short must be 4-12 lowercase alphanumeric or hyphen characters."
  }
}

variable "org_short" {
  description = "Non-sensitive lowercase organization prefix used in bucket names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,10}[a-z0-9]$", var.org_short))
    error_message = "org_short must be 2-12 lowercase alphanumeric or hyphen characters."
  }
}

variable "owner" {
  description = "Non-empty owning team tag."
  type        = string
  default     = "platform"

  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner must not be empty."
  }
}

variable "cost_center" {
  description = "Non-empty approved cost allocation tag."
  type        = string
  default     = "insurance-data-ai"

  validation {
    condition     = trimspace(var.cost_center) != ""
    error_message = "cost_center must not be empty."
  }
}

variable "data_classification" {
  description = "Highest classification represented by the foundation."
  type        = string
  default     = "restricted"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential, or restricted."
  }
}

variable "vpc_cidr" {
  description = "Approved non-conflicting RFC1918 VPC CIDR."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.vpc_cidr, 0)) && can(regex(
        "^(10\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.|192\\.168\\.)",
        var.vpc_cidr,
      ))
    )
    error_message = "vpc_cidr must be a valid RFC1918 IPv4 CIDR."
  }
}

variable "private_subnet_newbits" {
  description = "Additional bits used to derive the two private subnet CIDRs."
  type        = number
  default     = 4

  validation {
    condition     = floor(var.private_subnet_newbits) == var.private_subnet_newbits && var.private_subnet_newbits >= 1 && var.private_subnet_newbits <= 8
    error_message = "private_subnet_newbits must be an integer from 1 to 8."
  }
}

variable "private_subnet_netnums" {
  description = "Two distinct subnet numbers for deterministic cidrsubnet derivation."
  type        = list(number)
  default     = [0, 1]

  validation {
    condition = (
      length(var.private_subnet_netnums) == 2 &&
      length(distinct(var.private_subnet_netnums)) == 2 &&
      alltrue([
        for netnum in var.private_subnet_netnums :
        floor(netnum) == netnum && netnum >= 0 && netnum < pow(2, var.private_subnet_newbits)
      ])
    )
    error_message = "private_subnet_netnums must contain two distinct valid integers for private_subnet_newbits."
  }
}

variable "availability_zones" {
  description = "Exactly two distinct approved Sydney availability zones."
  type        = list(string)

  validation {
    condition = (
      length(var.availability_zones) == 2 &&
      length(distinct(var.availability_zones)) == 2 &&
      alltrue([
        for availability_zone in var.availability_zones : can(regex("^ap-southeast-2[a-z]$", availability_zone))
      ])
    )
    error_message = "availability_zones must contain two distinct ap-southeast-2 zones."
  }
}

variable "terraform_trusted_role_arns" {
  description = "Deferred V3 Terraform trust roles; unused by the V1 DEV root."
  type        = list(string)
  default     = []

  validation {
    condition = (
      alltrue([
        for arn in var.terraform_trusted_role_arns : can(regex(
          "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
          arn,
        ))
      ])
    )
    error_message = "terraform_trusted_role_arns must contain explicit same-account path-capable role ARNs."
  }
}

variable "kms_admin_role_arns" {
  description = "Explicit same-account administrators for platform and audit KMS keys."
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
    error_message = "kms_admin_role_arns must contain explicit same-account path-capable role ARNs."
  }
}
variable "allow_root_for_v1" {
  description = "Temporary V1 root KMS allowance."
  type        = bool
  default     = true
}

variable "lakeformation_admin_role_arns" {
  description = "Deferred V3 Lake Formation administrator roles; unused by the V1 DEV root."
  type        = list(string)
  default     = []

  validation {
    condition = (
      alltrue([
        for arn in var.lakeformation_admin_role_arns : can(regex(
          "^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$",
          arn,
        ))
      ])
    )
    error_message = "lakeformation_admin_role_arns must contain explicit same-account path-capable role ARNs."
  }
}

variable "data_engineer_role_arn" {
  description = "Deferred V3 DataEngineer role ARN; unused by the V1 DEV root."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.data_engineer_role_arn == null || can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.data_engineer_role_arn))
    error_message = "data_engineer_role_arn must be an explicit same-account path-capable role ARN."
  }
}

variable "analyst_role_arn" {
  description = "Deferred V3 Analyst role ARN; unused by the V1 DEV root."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.analyst_role_arn == null || can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.analyst_role_arn))
    error_message = "analyst_role_arn must be an explicit same-account path-capable role ARN."
  }
}

variable "ml_engineer_role_arn" {
  description = "Deferred V3 MLEngineer role ARN; unused by the V1 DEV root."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ml_engineer_role_arn == null || can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.ml_engineer_role_arn))
    error_message = "ml_engineer_role_arn must be an explicit same-account path-capable role ARN."
  }
}

variable "rag_application_role_arn" {
  description = "Deferred V3 RAGApplication role ARN; unused by the V1 DEV root."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.rag_application_role_arn == null || can(regex("^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.rag_application_role_arn))
    error_message = "rag_application_role_arn must be an explicit same-account path-capable role ARN."
  }
}

variable "data_noncurrent_retention_days" {
  description = "Approved noncurrent-version retention for the five data buckets."
  type        = number

  validation {
    condition     = floor(var.data_noncurrent_retention_days) == var.data_noncurrent_retention_days && var.data_noncurrent_retention_days >= 7 && var.data_noncurrent_retention_days <= 3650
    error_message = "data_noncurrent_retention_days must be an integer from 7 to 3650."
  }
}

variable "audit_noncurrent_retention_days" {
  description = "Approved noncurrent-version retention for audit logs."
  type        = number

  validation {
    condition     = floor(var.audit_noncurrent_retention_days) == var.audit_noncurrent_retention_days && var.audit_noncurrent_retention_days >= 30 && var.audit_noncurrent_retention_days <= 3650
    error_message = "audit_noncurrent_retention_days must be an integer from 30 to 3650."
  }
}

variable "audit_retention_days" {
  description = "Approved current-object retention for audit logs."
  type        = number

  validation {
    condition = (
      floor(var.audit_retention_days) == var.audit_retention_days &&
      var.audit_retention_days >= var.audit_noncurrent_retention_days &&
      var.audit_retention_days <= 3650
    )
    error_message = "audit_retention_days must be an integer no shorter than noncurrent retention and no longer than 3650 days."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention selected from AWS-supported values."
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
    error_message = "log_retention_days must be an AWS-supported value from 30 through 3653."
  }
}

variable "monthly_budget_usd" {
  description = "Human review threshold for the Phase 1 monthly DEV cost estimate; this does not create an AWS Budgets resource."
  type        = number

  validation {
    condition     = var.monthly_budget_usd >= 12 && var.monthly_budget_usd <= 100
    error_message = "monthly_budget_usd must be at least the approved USD 12 Phase 1 upper estimate and no more than USD 100 without a new cost review."
  }
}

variable "enable_quicksight" {
  type        = bool
  default     = false
  description = "Enable optional QuickSight dataset resources after account-level prerequisites are approved."
}

variable "quicksight_account_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Explicit QuickSight account ID; never infer or fabricate."
}

variable "quicksight_user_arn" {
  type        = string
  default     = null
  nullable    = true
  description = "Approved QuickSight user/group ARN."
}

variable "quicksight_namespace" {
  type    = string
  default = "default"
}

variable "quicksight_edition" {
  type        = string
  default     = null
  nullable    = true
  description = "Subscribed QuickSight edition (STANDARD or ENTERPRISE), recorded for the plan."
}
