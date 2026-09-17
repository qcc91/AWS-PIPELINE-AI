locals {
  trail_name               = "insurance-${var.environment}-management-trail"
  trail_arn                = "arn:aws:cloudtrail:ap-southeast-2:${var.account_id}:trail/${local.trail_name}"
  log_group_name           = "/insurance/${var.environment}/cloudtrail/audit"
  log_group_arn            = "arn:aws:logs:ap-southeast-2:${var.account_id}:log-group:${local.log_group_name}"
  topic_name               = "insurance-${var.environment}-critical-alerts"
  topic_arn                = "arn:aws:sns:ap-southeast-2:${var.account_id}:${local.topic_name}"
  operational_alarm_prefix = "insurance-${var.environment}"
  glue_failure_rule_name   = "${local.operational_alarm_prefix}-glue-job-failures"
  dms_failure_subscription = "${local.operational_alarm_prefix}-dms-task-failures"
}

resource "aws_kms_key" "audit" {
  description             = "${var.environment} audit, CloudTrail, CloudWatch Logs, and SNS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      var.allow_root_for_v1 ? [{ Sid = "EnableV1RootScopedAccess", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }, Action = ["kms:CancelKeyDeletion", "kms:CreateAlias", "kms:DeleteAlias", "kms:DescribeKey", "kms:DisableKey", "kms:DisableKeyRotation", "kms:EnableKey", "kms:EnableKeyRotation", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListGrants", "kms:ListKeyPolicies", "kms:ListResourceTags", "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource", "kms:UpdateAlias", "kms:UpdateKeyDescription", "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:ReEncryptFrom", "kms:ReEncryptTo"], Resource = "*" }] : [],
      [
        for role_index, role_arn in var.kms_admin_role_arns : {
          Sid    = "AllowAuditKeyAdministrator${role_index}"
          Effect = "Allow"
          Principal = {
            AWS = role_arn
          }
          Action = [
            "kms:CancelKeyDeletion",
            "kms:CreateGrant",
            "kms:DescribeKey",
            "kms:DisableKey",
            "kms:DisableKeyRotation",
            "kms:EnableKey",
            "kms:EnableKeyRotation",
            "kms:GetKeyPolicy",
            "kms:GetKeyRotationStatus",
            "kms:ListGrants",
            "kms:ListKeyPolicies",
            "kms:ListResourceTags",
            "kms:PutKeyPolicy",
            "kms:RevokeGrant",
            "kms:ScheduleKeyDeletion",
            "kms:TagResource",
            "kms:UntagResource",
            "kms:UpdateKeyDescription",
          ]
          Resource = "*"
        }
      ],
      [
        {
          Sid    = "AllowCloudTrailGenerateDataKey"
          Effect = "Allow"
          Principal = {
            Service = "cloudtrail.amazonaws.com"
          }
          Action   = "kms:GenerateDataKey*"
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = var.account_id
            }
            ArnEquals = {
              "aws:SourceArn"                            = local.trail_arn
              "kms:EncryptionContext:aws:cloudtrail:arn" = local.trail_arn
            }
          }
        },
        {
          Sid    = "AllowCloudTrailDescribeKey"
          Effect = "Allow"
          Principal = {
            Service = "cloudtrail.amazonaws.com"
          }
          Action   = "kms:DescribeKey"
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = var.account_id
            }
            ArnEquals = {
              "aws:SourceArn" = local.trail_arn
            }
          }
        },
        {
          Sid    = "AllowCloudWatchLogsEncryption"
          Effect = "Allow"
          Principal = {
            Service = "logs.ap-southeast-2.amazonaws.com"
          }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:GenerateDataKey*",
            "kms:ReEncrypt*",
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "kms:EncryptionContext:aws:logs:arn" = local.log_group_arn
            }
          }
        },
        {
          Sid    = "AllowSnsEncryption"
          Effect = "Allow"
          Principal = {
            Service = "sns.amazonaws.com"
          }
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey*",
          ]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = var.account_id
            }
            ArnEquals = {
              "aws:SourceArn" = local.topic_arn
            }
          }
        }
      ],
      var.enable_operational_alerting ? [
        {
          Sid    = "AllowOperationalPublishersToUseEncryptedTopic"
          Effect = "Allow"
          Principal = {
            Service = [
              "cloudwatch.amazonaws.com",
              "dms.amazonaws.com",
              "events.amazonaws.com",
            ]
          }
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey*",
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "kms:EncryptionContext:aws:sns:topicArn" = local.topic_arn
            }
          }
        }
      ] : [],
    )
  })

  tags = merge(var.tags, {
    Purpose = "audit-encryption"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "audit" {
  name          = "alias/insurance/${var.environment}/audit"
  target_key_id = aws_kms_key.audit.key_id
}

resource "aws_s3_bucket" "audit" {
  bucket        = var.bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Purpose = "audit-logs"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.audit.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  depends_on = [aws_s3_bucket_versioning.audit]

  rule {
    id     = "retain-noncurrent-audit-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.audit_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.audit_noncurrent_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.audit.arn,
          "${aws_s3_bucket.audit.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowCloudTrailBucketAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.audit.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
          ArnEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.audit.arn
  tags              = var.tags
}

resource "aws_iam_role" "cloudtrail_delivery" {
  name = "insurance-${var.environment}-cloudtrail-delivery-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailService"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudtrail_delivery" {
  name = "write-target-cloudwatch-log-streams"
  role = aws_iam_role.cloudtrail_delivery.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOnlyTargetLogStreams"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.audit.arn}:log-stream:*"
      }
    ]
  })
}

resource "aws_sns_topic" "alerts" {
  name              = local.topic_name
  kms_master_key_id = aws_kms_key.audit.arn
  tags              = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_sns_topic_policy" "operational_alerts" {
  count = var.enable_operational_alerting ? 1 : 0

  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountOwner"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "sns:AddPermission",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish",
          "sns:RemovePermission",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
        ]
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = { "AWS:SourceOwner" = var.account_id }
        }
      },
      {
        Sid       = "AllowCloudWatchAlarmPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:ap-southeast-2:${var.account_id}:alarm:${local.operational_alarm_prefix}-*" }
        }
      },
      {
        Sid       = "AllowGlueFailureRulePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
      },
      {
        Sid       = "AllowDmsFailurePublish"
        Effect    = "Allow"
        Principal = { Service = "dms.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = "arn:aws:dms:ap-southeast-2:${var.account_id}:es:${local.dms_failure_subscription}" }
        }
      },
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "workflow_failures" {
  for_each = var.enable_operational_alerting ? var.workflow_state_machine_arns : {}

  alarm_name          = "${local.operational_alarm_prefix}-${each.key}-workflow-failures"
  alarm_description   = "${upper(var.environment)} ${each.key} Step Functions execution failed, timed out, or was aborted. Investigate the execution ARN and pipeline run_id."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = []

  metric_query {
    id          = "total"
    expression  = "FILL(failed, 0) + FILL(timedout, 0) + FILL(aborted, 0)"
    label       = "Unsuccessful executions"
    return_data = true
  }

  metric_query {
    id          = "failed"
    return_data = false
    metric {
      metric_name = "ExecutionsFailed"
      namespace   = "AWS/States"
      period      = 300
      stat        = "Sum"
      dimensions  = { StateMachineArn = each.value }
    }
  }

  metric_query {
    id          = "timedout"
    return_data = false
    metric {
      metric_name = "ExecutionsTimedOut"
      namespace   = "AWS/States"
      period      = 300
      stat        = "Sum"
      dimensions  = { StateMachineArn = each.value }
    }
  }

  metric_query {
    id          = "aborted"
    return_data = false
    metric {
      metric_name = "ExecutionsAborted"
      namespace   = "AWS/States"
      period      = 300
      stat        = "Sum"
      dimensions  = { StateMachineArn = each.value }
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "codepipeline_failures" {
  count = var.enable_operational_alerting && var.codepipeline_name != null ? 1 : 0

  alarm_name          = "${local.operational_alarm_prefix}-codepipeline-failures"
  alarm_description   = "${upper(var.environment)} CodePipeline execution failed. Inspect the failed stage and source revision before retrying."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedPipelineExecutions"
  namespace           = "AWS/CodePipeline"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions          = { PipelineName = var.codepipeline_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "codebuild_failures" {
  count = var.enable_operational_alerting && length(var.codebuild_project_names) > 0 ? 1 : 0

  alarm_name          = "${local.operational_alarm_prefix}-codebuild-failures"
  alarm_description   = "${upper(var.environment)} CodeBuild deployment project failed. Inspect the build ID and preserve the PROD approval boundary."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "total"
    expression  = join(" + ", [for id in sort(keys(var.codebuild_project_names)) : "FILL(${id}, 0)"])
    label       = "Failed V4B builds"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = var.codebuild_project_names
    content {
      id          = metric_query.key
      return_data = false
      metric {
        metric_name = "FailedBuilds"
        namespace   = "AWS/CodeBuild"
        period      = 300
        stat        = "Sum"
        dimensions  = { ProjectName = metric_query.value }
      }
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "glue_job_failures" {
  count = var.enable_operational_alerting && length(var.glue_job_names) > 0 ? 1 : 0

  name        = local.glue_failure_rule_name
  description = "Routes terminal failures from the approved DEV Glue jobs to the operational SNS topic."
  event_pattern = jsonencode({
    source        = ["aws.glue"]
    "detail-type" = ["Glue Job State Change"]
    detail = {
      jobName = sort(tolist(var.glue_job_names))
      state   = ["FAILED", "STOPPED", "TIMEOUT"]
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "glue_job_failures" {
  count = var.enable_operational_alerting && length(var.glue_job_names) > 0 ? 1 : 0

  rule = aws_cloudwatch_event_rule.glue_job_failures[0].name
  arn  = aws_sns_topic.alerts.arn

  depends_on = [aws_sns_topic_policy.operational_alerts]
}

resource "aws_dms_event_subscription" "task_failures" {
  count = var.enable_operational_alerting && var.dms_replication_task_id != null ? 1 : 0

  name             = local.dms_failure_subscription
  sns_topic_arn    = aws_sns_topic.alerts.arn
  source_type      = "replication-task"
  source_ids       = [var.dms_replication_task_id]
  event_categories = ["failure"]
  enabled          = true
  tags             = var.tags

  depends_on = [aws_sns_topic_policy.operational_alerts]
}

resource "aws_cloudtrail" "management" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.audit.id
  kms_key_id                    = aws_kms_key.audit.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.audit.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_delivery.arn
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_logging                = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type                  = "All"
    include_management_events        = true
    exclude_management_event_sources = []
  }

  tags = var.tags

  depends_on = [aws_s3_bucket_policy.audit]
}
