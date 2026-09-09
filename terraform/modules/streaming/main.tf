locals {
  lakehouse_arn = "arn:aws:s3:::${var.lakehouse_bucket_name}"
  control_arn   = "arn:aws:s3:::${var.control_bucket_name}"
  stream_name   = "insurance-${var.environment}-events"
  firehose_name = "insurance-${var.environment}-events-to-s3"
  script_key    = "artifacts/glue/glue_streaming_pipeline.py"
}

resource "aws_s3_bucket_notification" "lakehouse_eventbridge" {
  bucket      = var.lakehouse_bucket_name
  eventbridge = true
}

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/vendedlogs/states/insurance-${var.environment}-streaming"
  retention_in_days = 30
  tags              = merge(var.tags, { Purpose = "stream-orchestration-logs" })
}

resource "aws_iam_role" "step_functions" {
  name               = "insurance-${var.environment}-stream-step-functions-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "states.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "stream-orchestration" })
}

resource "aws_iam_role_policy" "step_functions" {
  name   = "start-and-monitor-stream-glue-job"
  role   = aws_iam_role.step_functions.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["glue:BatchStopJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:StartJobRun"], Resource = "*" }, { Effect = "Allow", Action = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"], Resource = "*" }] })
}

resource "aws_sfn_state_machine" "events" {
  name       = "insurance-${var.environment}-streaming"
  role_arn   = aws_iam_role.step_functions.arn
  definition = jsonencode({ Comment = "V1 Firehose stream objects to Iceberg", StartAt = "RunStreamingGlue", States = { RunStreamingGlue = { Type = "Task", Resource = "arn:aws:states:::glue:startJobRun.sync", Parameters = { JobName = aws_glue_job.events.name, Arguments = { "--STREAM_BUCKET.$" = "$.detail.bucket.name", "--STREAM_PREFIX" = "stream", "--RUN_ID.$" = "$.id" } }, End = true } } })
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }
  tracing_configuration {
    enabled = false
  }
  tags       = merge(var.tags, { Purpose = "stream-orchestration" })
  depends_on = [aws_iam_role_policy.step_functions]
}

resource "aws_iam_role" "eventbridge" {
  name               = "insurance-${var.environment}-stream-eventbridge-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "stream-event-trigger" })
}

resource "aws_iam_role_policy" "eventbridge" {
  name   = "start-stream-state-machine"
  role   = aws_iam_role.eventbridge.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "states:StartExecution", Resource = aws_sfn_state_machine.events.arn }] })
}

resource "aws_cloudwatch_event_rule" "lakehouse_stream_object_created" {
  name           = "insurance-${var.environment}-stream-object-created"
  description    = "Start streaming Glue processing after Firehose creates a stream object."
  event_bus_name = "default"
  event_pattern  = jsonencode({ source = ["aws.s3"], "detail-type" = ["Object Created"], detail = { bucket = { name = [var.lakehouse_bucket_name] }, object = { key = [{ prefix = "stream/" }] } } })
  tags           = merge(var.tags, { Purpose = "stream-event-trigger" })
}

resource "aws_cloudwatch_event_target" "stream_state_machine" {
  rule      = aws_cloudwatch_event_rule.lakehouse_stream_object_created.name
  target_id = "stream-state-machine"
  arn       = aws_sfn_state_machine.events.arn
  role_arn  = aws_iam_role.eventbridge.arn
}

resource "aws_kinesis_stream" "events" {
  name             = local.stream_name
  shard_count      = 1
  retention_period = 24
  encryption_type  = "KMS"
  kms_key_id       = var.kms_key_arn
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
  tags = merge(var.tags, { Purpose = "streaming-events" })
}

# Attach this scoped policy to the approved producer execution identity during
# deployment. The module deliberately does not create a human/user identity.
resource "aws_iam_policy" "producer" {
  name = "insurance-${var.environment}-stream-producer"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kinesis:DescribeStreamSummary", "kinesis:PutRecord", "kinesis:PutRecords"]
      Resource = aws_kinesis_stream.events.arn
      }, {
      Effect   = "Allow"
      Action   = ["kms:DescribeKey", "kms:GenerateDataKey"]
      Resource = var.kms_key_arn
    }]
  })
  tags = merge(var.tags, { Purpose = "stream-producer-least-privilege" })
}

resource "aws_iam_role" "firehose" {
  name               = "insurance-${var.environment}-stream-firehose-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "firehose.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "stream-firehose-delivery" })
}

resource "aws_iam_role_policy" "firehose" {
  name = "stream-firehose-s3-access"
  role = aws_iam_role.firehose.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = local.lakehouse_arn },
    { Effect = "Allow", Action = ["s3:AbortMultipartUpload", "s3:GetObject", "s3:PutObject"], Resource = "${local.lakehouse_arn}/stream/*" },
    { Effect = "Allow", Action = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"], Resource = aws_kinesis_stream.events.arn },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"], Resource = var.kms_key_arn }
  ] })
}

resource "aws_kinesis_firehose_delivery_stream" "events" {
  name        = local.firehose_name
  destination = "extended_s3"
  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.events.arn
    role_arn           = aws_iam_role.firehose.arn
  }
  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = local.lakehouse_arn
    prefix              = "stream/"
    error_output_prefix = "stream-errors/"
    buffering_size      = 1
    buffering_interval  = 60
    compression_format  = "GZIP"
    kms_key_arn         = var.kms_key_arn
  }
  tags       = merge(var.tags, { Purpose = "stream-firehose-to-s3" })
  depends_on = [aws_iam_role_policy.firehose]
}

resource "aws_s3_object" "glue_script" {
  bucket                 = var.control_bucket_name
  key                    = local.script_key
  source                 = var.glue_script_path
  source_hash            = filemd5(var.glue_script_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "text/x-python"
}

resource "aws_iam_role" "glue" {
  name               = "insurance-${var.environment}-stream-glue-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "glue.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "stream-iceberg-processing" })
}

resource "aws_iam_role_policy" "glue" {
  name = "stream-iceberg-data-access"
  role = aws_iam_role.glue.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = [local.lakehouse_arn, local.control_arn] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"], Resource = ["${local.lakehouse_arn}/*", "${local.control_arn}/*"] },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:ReEncrypt*"], Resource = var.kms_key_arn },
    { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:GetTables", "glue:CreateTable", "glue:UpdateTable", "glue:CreateDatabase"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" }
  ] })
}

resource "aws_glue_job" "events" {
  name              = "insurance-${var.environment}-stream-iceberg"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15
  command {
    name            = "glueetl"
    script_location = "s3://${var.control_bucket_name}/${local.script_key}"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language"    = "python", "--datalake-formats" = "iceberg", "--STREAM_PREFIX" = "stream",
    "--STREAM_BUCKET"   = var.lakehouse_bucket_name, "--LAKEHOUSE_BUCKET" = var.lakehouse_bucket_name,
    "--BRONZE_DATABASE" = var.glue_database_names["bronze"], "--SILVER_DATABASE" = var.glue_database_names["silver"], "--GOLD_DATABASE" = var.glue_database_names["gold"], "--RUN_ID" = "manual"
  }
  execution_property {
    max_concurrent_runs = 1
  }
  depends_on = [aws_s3_object.glue_script, aws_iam_role_policy.glue]
  tags       = merge(var.tags, { Purpose = "stream-iceberg-processing" })
}
