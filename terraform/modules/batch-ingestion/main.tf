locals {
  landing_bucket_arn    = "arn:aws:s3:::${var.landing_bucket_name}"
  lakehouse_bucket_arn  = "arn:aws:s3:::${var.lakehouse_bucket_name}"
  control_bucket_arn    = "arn:aws:s3:::${var.control_bucket_name}"
  quarantine_bucket_arn = "arn:aws:s3:::${var.quarantine_bucket_name}"
  glue_catalog_arn      = "arn:aws:glue:${var.aws_region}:${var.account_id}:catalog"
  glue_database_arns    = [for layer in ["bronze", "silver", "gold"] : "arn:aws:glue:${var.aws_region}:${var.account_id}:database/${var.glue_database_names[layer]}"]
  glue_table_arns       = [for layer in ["bronze", "silver", "gold"] : "arn:aws:glue:${var.aws_region}:${var.account_id}:table/${var.glue_database_names[layer]}/*"]
  glue_script_key       = "artifacts/glue/glue_claim_pipeline.py"
  state_machine_name    = "insurance-${var.environment}-batch-claim-lakehouse"
  job_name              = "insurance-${var.environment}-batch-claim-lakehouse"
}

resource "aws_s3_bucket_notification" "landing_eventbridge" {
  bucket      = var.landing_bucket_name
  eventbridge = true
}

resource "aws_s3_object" "glue_script" {
  bucket                 = var.control_bucket_name
  key                    = local.glue_script_key
  source                 = var.glue_script_path
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "text/x-python"
  source_hash            = filemd5(var.glue_script_path)
  tags                   = merge(var.tags, { Purpose = "glue-job-artifact" })
}

resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws-glue/jobs/${local.job_name}"
  retention_in_days = 30
  tags              = merge(var.tags, { Purpose = "batch-glue-logs" })
}

resource "aws_cloudwatch_log_group" "glue_stage" {
  for_each = toset(["silver", "gold"])

  name              = "/aws-glue/jobs/${local.job_name}-${each.key}"
  retention_in_days = 30
  tags              = merge(var.tags, { Purpose = "batch-${each.key}-glue-logs", Stage = each.key })
}

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/vendedlogs/states/${local.state_machine_name}"
  retention_in_days = 30
  tags              = merge(var.tags, { Purpose = "batch-orchestration-logs" })
}

resource "aws_iam_role" "glue" {
  name = "insurance-${var.environment}-batch-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Purpose = "batch-glue-execution" })
}

resource "aws_iam_role_policy" "glue" {
  name = "batch-iceberg-data-access"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LandingList"
        Effect    = "Allow"
        Action    = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource  = local.landing_bucket_arn
        Condition = { StringLike = { "s3:prefix" = ["${var.batch_key_prefix}*"] } }
      },
      {
        Sid      = "ReadLandingObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${local.landing_bucket_arn}/${var.batch_key_prefix}*"
      },
      {
        Sid      = "LakehouseList"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [local.lakehouse_bucket_arn, local.control_bucket_arn, local.quarantine_bucket_arn]
      },
      {
        Sid      = "LakehouseObjects"
        Effect   = "Allow"
        Action   = ["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = ["${local.lakehouse_bucket_arn}/*", "${local.control_bucket_arn}/*"]
      },
      {
        Sid      = "QuarantineObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${local.quarantine_bucket_arn}/quarantine/v2/*"
      },
      {
        Sid      = "UsePlatformKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*"]
        Resource = var.kms_key_arn
      },
      {
        Sid      = "GlueCatalogForLayers"
        Effect   = "Allow"
        Action   = ["glue:CreateTable", "glue:CreateDatabase", "glue:DeleteTable", "glue:GetDatabase", "glue:GetTable", "glue:GetTables", "glue:UpdateTable"]
        Resource = concat([local.glue_catalog_arn], local.glue_database_arns, local.glue_table_arns)
      },
      {
        Sid      = "WriteJobLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [aws_cloudwatch_log_group.glue.arn, "${aws_cloudwatch_log_group.glue.arn}:*"]
      }
    ]
  })
}

resource "aws_glue_job" "batch" {
  name              = local.job_name
  role_arn          = aws_iam_role.glue.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  max_retries       = 0
  timeout           = 15

  command {
    name            = "glueetl"
    script_location = "s3://${var.control_bucket_name}/${local.glue_script_key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--datalake-formats"                 = "iceberg"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "false"
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.glue.name
    "--conf" = join(" ", [
      "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
      "--conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog",
      "--conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog",
      "--conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO",
      "--conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.lakehouse_bucket_name}/lakehouse/",
    ])
    "--TempDir"           = "s3://${var.control_bucket_name}/glue-temp/"
    "--PROCESSING_STAGE"  = "bronze"
    "--RUN_ID"            = "manual"
    "--LANDING_BUCKET"    = var.landing_bucket_name
    "--LANDING_KEY"       = "manual"
    "--LAKEHOUSE_BUCKET"  = var.lakehouse_bucket_name
    "--BRONZE_DATABASE"   = var.glue_database_names["bronze"]
    "--SILVER_DATABASE"   = var.glue_database_names["silver"]
    "--GOLD_DATABASE"     = var.glue_database_names["gold"]
    "--CONTROL_BUCKET"    = var.control_bucket_name
    "--CONTROL_PREFIX"    = "control/v2"
    "--QUARANTINE_BUCKET" = var.quarantine_bucket_name
    "--QUARANTINE_PREFIX" = "quarantine/v2"
  }

  execution_property { max_concurrent_runs = 1 }
  depends_on = [aws_s3_object.glue_script, aws_cloudwatch_log_group.glue]
  tags       = merge(var.tags, { Purpose = "batch-iceberg-processing", Stage = "bronze" })
}

resource "aws_glue_job" "stage" {
  for_each = toset(["silver", "gold"])

  name              = "${local.job_name}-${each.key}"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  max_retries       = 0
  timeout           = 15

  command {
    name            = "glueetl"
    script_location = "s3://${var.control_bucket_name}/${local.glue_script_key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--datalake-formats"                 = "iceberg"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "false"
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.glue_stage[each.key].name
    "--conf" = join(" ", [
      "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
      "--conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog",
      "--conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog",
      "--conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO",
      "--conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.lakehouse_bucket_name}/lakehouse/",
    ])
    "--TempDir"           = "s3://${var.control_bucket_name}/glue-temp/"
    "--PROCESSING_STAGE"  = each.key
    "--RUN_ID"            = "manual"
    "--LANDING_BUCKET"    = var.landing_bucket_name
    "--LANDING_KEY"       = "manual"
    "--LAKEHOUSE_BUCKET"  = var.lakehouse_bucket_name
    "--BRONZE_DATABASE"   = var.glue_database_names["bronze"]
    "--SILVER_DATABASE"   = var.glue_database_names["silver"]
    "--GOLD_DATABASE"     = var.glue_database_names["gold"]
    "--CONTROL_BUCKET"    = var.control_bucket_name
    "--CONTROL_PREFIX"    = "control/v2"
    "--QUARANTINE_BUCKET" = var.quarantine_bucket_name
    "--QUARANTINE_PREFIX" = "quarantine/v2"
  }

  execution_property { max_concurrent_runs = 1 }
  depends_on = [aws_s3_object.glue_script, aws_cloudwatch_log_group.glue_stage]
  tags       = merge(var.tags, { Purpose = "batch-iceberg-processing", Stage = each.key })
}

resource "aws_iam_role" "step_functions" {
  name = "insurance-${var.environment}-batch-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Purpose = "batch-orchestration" })
}

resource "aws_iam_role_policy" "step_functions" {
  name = "start-and-monitor-glue-job"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["glue:BatchStopJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:StartJobRun"]
        # AWS Step Functions optimized Glue integration requires Resource="*".
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${local.control_bucket_arn}/control/v2/pipeline_runs/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "batch" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "V2 Batch Bronze, Silver, and Gold with independent retry and failure boundaries"
    StartAt = "RunBronze"
    States = {
      RunBronze = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.batch.name
          Arguments = {
            "--LANDING_BUCKET.$" = "$.detail.bucket.name"
            "--LANDING_KEY.$"    = "$.detail.object.key"
            "--RUN_ID.$"         = "$.id"
            "--PROCESSING_STAGE" = "bronze"
          }
        }
        ResultPath = "$.bronze_result"
        Retry = [{
          ErrorEquals     = ["Glue.ConcurrentRunsExceededException", "States.Timeout"]
          IntervalSeconds = 10
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.failure", Next = "RecordBronzeFailure" }]
        Next  = "RunSilver"
      }
      RunSilver = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.stage["silver"].name
          Arguments = {
            "--LANDING_BUCKET.$" = "$.detail.bucket.name"
            "--LANDING_KEY.$"    = "$.detail.object.key"
            "--RUN_ID.$"         = "$.id"
            "--PROCESSING_STAGE" = "silver"
          }
        }
        ResultPath = "$.silver_result"
        Retry = [{
          ErrorEquals     = ["Glue.ConcurrentRunsExceededException", "States.Timeout"]
          IntervalSeconds = 10
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.failure", Next = "RecordSilverFailure" }]
        Next  = "RunGold"
      }
      RunGold = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.stage["gold"].name
          Arguments = {
            "--LANDING_BUCKET.$" = "$.detail.bucket.name"
            "--LANDING_KEY.$"    = "$.detail.object.key"
            "--RUN_ID.$"         = "$.id"
            "--PROCESSING_STAGE" = "gold"
          }
        }
        ResultPath = "$.gold_result"
        Retry = [{
          ErrorEquals     = ["Glue.ConcurrentRunsExceededException", "States.Timeout"]
          IntervalSeconds = 10
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.failure", Next = "RecordGoldFailure" }]
        End   = true
      }
      RecordBronzeFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:putObject"
        Parameters = {
          Bucket               = var.control_bucket_name
          "Key.$"              = "States.Format('control/v2/pipeline_runs/{}/bronze-failure.json', $.id)"
          "Body.$"             = "States.JsonToString($.failure)"
          ServerSideEncryption = "aws:kms"
          SsekmsKeyId          = var.kms_key_arn
          ContentType          = "application/json"
        }
        ResultPath = "$.failure_audit"
        Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.failure_audit_error", Next = "PipelineFailed" }]
        Next       = "PipelineFailed"
      }
      RecordSilverFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:putObject"
        Parameters = {
          Bucket               = var.control_bucket_name
          "Key.$"              = "States.Format('control/v2/pipeline_runs/{}/silver-failure.json', $.id)"
          "Body.$"             = "States.JsonToString($.failure)"
          ServerSideEncryption = "aws:kms"
          SsekmsKeyId          = var.kms_key_arn
          ContentType          = "application/json"
        }
        ResultPath = "$.failure_audit"
        Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.failure_audit_error", Next = "PipelineFailed" }]
        Next       = "PipelineFailed"
      }
      RecordGoldFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:putObject"
        Parameters = {
          Bucket               = var.control_bucket_name
          "Key.$"              = "States.Format('control/v2/pipeline_runs/{}/gold-failure.json', $.id)"
          "Body.$"             = "States.JsonToString($.failure)"
          ServerSideEncryption = "aws:kms"
          SsekmsKeyId          = var.kms_key_arn
          ContentType          = "application/json"
        }
        ResultPath = "$.failure_audit"
        Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.failure_audit_error", Next = "PipelineFailed" }]
        Next       = "PipelineFailed"
      }
      PipelineFailed = {
        Type  = "Fail"
        Error = "BatchMedallionStageFailed"
        Cause = "A V2 Batch stage exhausted its bounded retries; execution history and stage audit identify the failure."
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tracing_configuration { enabled = false }
  tags       = merge(var.tags, { Purpose = "batch-orchestration" })
  depends_on = [aws_iam_role_policy.step_functions]
}

resource "aws_iam_role" "eventbridge" {
  name = "insurance-${var.environment}-batch-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Purpose = "batch-event-trigger" })
}

resource "aws_iam_role_policy" "eventbridge" {
  name = "start-batch-state-machine"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.batch.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "landing_object_created" {
  name           = "insurance-${var.environment}-batch-landing-object-created"
  description    = "Start the V1 claim pipeline after a broker CSV is fully created in landing."
  event_bus_name = "default"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [var.landing_bucket_name] }
      object = { key = [{ prefix = var.batch_key_prefix }] }
    }
  })

  tags = merge(var.tags, { Purpose = "batch-event-trigger" })
}

resource "aws_cloudwatch_event_target" "state_machine" {
  rule      = aws_cloudwatch_event_rule.landing_object_created.name
  target_id = "batch-state-machine"
  arn       = aws_sfn_state_machine.batch.arn
  role_arn  = aws_iam_role.eventbridge.arn
}
