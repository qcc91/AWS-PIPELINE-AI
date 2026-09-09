locals {
  name                 = "insurance-${var.environment}-cdc"
  landing_bucket_arn   = "arn:aws:s3:::${var.landing_bucket_name}"
  lakehouse_bucket_arn = "arn:aws:s3:::${var.lakehouse_bucket_name}"
  control_bucket_arn   = "arn:aws:s3:::${var.control_bucket_name}"
  dms_prefix           = "oltp"
  cdc_job_name         = "insurance-${var.environment}-cdc-iceberg"
  seed_job_name        = "insurance-${var.environment}-cdc-sql-bootstrap"
  state_machine_name   = "insurance-${var.environment}-cdc-iceberg"
  glue_catalog_arn     = "arn:aws:glue:${var.aws_region}:${var.account_id}:catalog"
  glue_database_arns   = [for layer in ["bronze", "silver", "gold"] : "arn:aws:glue:${var.aws_region}:${var.account_id}:database/${var.glue_database_names[layer]}"]
  glue_table_arns      = [for layer in ["bronze", "silver", "gold"] : "arn:aws:glue:${var.aws_region}:${var.account_id}:table/${var.glue_database_names[layer]}/*"]
}

resource "aws_security_group" "dms" {
  name        = "${local.name}-dms"
  description = "Egress-only security group for the DEV DMS replication instance."
  vpc_id      = var.vpc_id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Purpose = "cdc-dms-network" })
}

resource "aws_security_group" "glue" {
  name        = "${local.name}-glue"
  description = "Glue SQL bootstrap access to the private RDS source."
  vpc_id      = var.vpc_id
  ingress {
    description = "Spark driver and executors communicate within the Glue security group."
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
    self        = true
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Purpose = "cdc-glue-network" })
}

resource "aws_security_group" "secrets_endpoint" {
  name        = "${local.name}-secrets-endpoint"
  description = "HTTPS access to the private Secrets Manager endpoint."
  vpc_id      = var.vpc_id
  ingress {
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    security_groups = [aws_security_group.dms.id, aws_security_group.glue.id]
  }
  tags = merge(var.tags, { Purpose = "cdc-secrets-endpoint" })
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "Private PostgreSQL source access from DMS and Glue only."
  vpc_id      = var.vpc_id
  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.dms.id, aws_security_group.glue.id]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Purpose = "cdc-rds-network" })
}

resource "aws_db_subnet_group" "source" {
  name       = local.name
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Purpose = "cdc-rds-subnet" })
}

resource "aws_db_parameter_group" "source" {
  name   = local.name
  family = "postgres16"
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
  }
  tags = merge(var.tags, { Purpose = "cdc-rds-logical-replication" })
}

resource "aws_db_instance" "source" {
  identifier              = local.name
  engine                  = "postgres"
  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_class
  allocated_storage       = 20
  max_allocated_storage   = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  kms_key_id              = var.kms_key_arn
  db_name                 = var.database_name
  username                = var.master_username
  password                = random_password.source.result
  port                    = 5432
  db_subnet_group_name    = aws_db_subnet_group.source.name
  parameter_group_name    = aws_db_parameter_group.source.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 1
  copy_tags_to_snapshot   = true
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
  lifecycle {
    prevent_destroy = true
  }
  tags = merge(var.tags, { Purpose = "cdc-postgresql-source" })
}

resource "random_password" "source" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "source" {
  name                    = "${local.name}-postgres"
  description             = "Terraform-managed V1 PostgreSQL credentials for DMS and Glue."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
  tags                    = merge(var.tags, { Purpose = "cdc-postgres-credentials" })
}

resource "aws_secretsmanager_secret_version" "source" {
  secret_id = aws_secretsmanager_secret.source.id
  secret_string = jsonencode({
    engine               = "postgres"
    host                 = aws_db_instance.source.address
    username             = var.master_username
    password             = random_password.source.result
    dbname               = var.database_name
    port                 = 5432
    dbInstanceIdentifier = aws_db_instance.source.identifier
  })
}

resource "aws_iam_role" "dms_s3" {
  name = "${local.name}-dms-s3-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "dms.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = merge(var.tags, { Purpose = "cdc-dms-s3-access" })
}

resource "aws_iam_role_policy" "dms_s3" {
  name = "write-oltp-cdc-to-s3"
  role = aws_iam_role.dms_s3.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = local.landing_bucket_arn },
      { Effect = "Allow", Action = ["s3:AbortMultipartUpload", "s3:ListMultipartUploadParts", "s3:PutObject"], Resource = "${local.landing_bucket_arn}/${local.dms_prefix}/*" },
      { Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"], Resource = var.kms_key_arn },
    ]
  })
}

resource "aws_iam_role" "dms_secrets" {
  name = "${local.name}-dms-secrets-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "dms.${var.aws_region}.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = merge(var.tags, { Purpose = "cdc-dms-secret-access" })
}

resource "aws_iam_role_policy" "dms_secrets" {
  name = "read-rds-managed-secret"
  role = aws_iam_role.dms_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.source.arn },
      { Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey"], Resource = var.kms_key_arn },
    ]
  })
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.secrets_endpoint.id]
  private_dns_enabled = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = [aws_iam_role.dms_secrets.arn, aws_iam_role.glue.arn] }
      Action    = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
      Resource  = aws_secretsmanager_secret.source.arn
    }]
  })
  tags = merge(var.tags, { Purpose = "cdc-secrets-endpoint" })
}

resource "aws_dms_replication_subnet_group" "source" {
  replication_subnet_group_id          = replace(local.name, "-", "")
  replication_subnet_group_description = "Private subnets for DEV PostgreSQL CDC"
  subnet_ids                           = var.private_subnet_ids
  tags                                 = merge(var.tags, { Purpose = "cdc-dms-subnet" })
}

resource "aws_dms_replication_instance" "source" {
  replication_instance_id     = replace(local.name, "-", "")
  replication_instance_class  = var.dms_instance_class
  allocated_storage           = 50
  engine_version              = "3.6.1"
  publicly_accessible         = false
  multi_az                    = false
  vpc_security_group_ids      = [aws_security_group.dms.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.source.id
  tags                        = merge(var.tags, { Purpose = "cdc-dms-replication" })
}

resource "aws_dms_endpoint" "postgres" {
  endpoint_id                     = replace("${local.name}-postgres", "-", "")
  endpoint_type                   = "source"
  engine_name                     = "postgres"
  ssl_mode                        = "require"
  database_name                   = var.database_name
  secrets_manager_access_role_arn = aws_iam_role.dms_secrets.arn
  secrets_manager_arn             = aws_secretsmanager_secret.source.arn
  extra_connection_attributes     = "secretsManagerEndpointOverride=${aws_vpc_endpoint.secrets_manager.dns_entry[0].dns_name}"
  postgres_settings {
    slot_name   = "insurance_${var.environment}_cdc_slot"
    plugin_name = "test-decoding"
  }
  tags = merge(var.tags, { Purpose = "cdc-postgres-source-endpoint" })
  depends_on = [
    aws_secretsmanager_secret_version.source,
    aws_vpc_endpoint.secrets_manager,
  ]
}

resource "aws_dms_s3_endpoint" "s3" {
  endpoint_id                       = replace("${local.name}-s3", "-", "")
  endpoint_type                     = "target"
  bucket_name                       = var.landing_bucket_name
  bucket_folder                     = local.dms_prefix
  service_access_role_arn           = aws_iam_role.dms_s3.arn
  data_format                       = "csv"
  encryption_mode                   = "SSE_KMS"
  server_side_encryption_kms_key_id = var.kms_key_arn
  include_op_for_full_load          = true
  cdc_inserts_and_updates           = false
  cdc_inserts_only                  = false
  timestamp_column_name             = "_dms_timestamp"
  add_column_name                   = true
  tags                              = merge(var.tags, { Purpose = "cdc-s3-target-endpoint" })
}

resource "aws_dms_replication_task" "source" {
  replication_task_id      = replace(local.name, "-", "")
  migration_type           = "full-load-and-cdc"
  replication_instance_arn = aws_dms_replication_instance.source.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.postgres.endpoint_arn
  target_endpoint_arn      = aws_dms_s3_endpoint.s3.endpoint_arn
  table_mappings = jsonencode({
    rules = [
      for table_name in ["customers", "policies", "products", "claims", "payments"] : {
        "rule-type"      = "selection", "rule-id" = table_name, "rule-name" = table_name,
        "object-locator" = { "schema-name" = "public", "table-name" = table_name }, "rule-action" = "include"
      }
    ]
  })
  replication_task_settings = jsonencode({
    Logging          = { EnableLogging = true, EnableLogContext = true }
    FullLoadSettings = { TargetTablePrepMode = "DO_NOTHING", CreatePkAfterFullLoad = false, StopTaskCachedChangesApplied = false, StopTaskCachedChangesNotApplied = false }
    TargetMetadata   = { TargetSchema = "", SupportLobs = true, FullLobMode = false, LobChunkSize = 64, LimitedSizeLobMode = true, LobMaxSize = 32 }
  })
  tags = merge(var.tags, { Purpose = "cdc-full-load-and-cdc-task" })
}

resource "aws_s3_object" "cdc_script" {
  bucket                 = var.control_bucket_name
  key                    = "artifacts/glue/glue_cdc_pipeline.py"
  source                 = var.cdc_script_path
  source_hash            = filemd5(var.cdc_script_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "text/x-python"
  tags                   = merge(var.tags, { Purpose = "cdc-glue-artifact" })
}

resource "aws_s3_object" "seed_script" {
  bucket                 = var.control_bucket_name
  key                    = "artifacts/glue/glue_cdc_sql_bootstrap.py"
  source                 = var.seed_script_path
  source_hash            = filemd5(var.seed_script_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "text/x-python"
  tags                   = merge(var.tags, { Purpose = "cdc-seed-artifact" })
}

resource "aws_s3_object" "schema_sql" {
  bucket                 = var.control_bucket_name
  key                    = "artifacts/sql/cdc_schema.sql"
  source                 = var.schema_sql_path
  source_hash            = filemd5(var.schema_sql_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "application/sql"
  tags                   = merge(var.tags, { Purpose = "cdc-schema-artifact" })
}

resource "aws_s3_object" "seed_sql" {
  bucket                 = var.control_bucket_name
  key                    = "artifacts/sql/cdc_seed.sql"
  source                 = var.seed_sql_path
  source_hash            = filemd5(var.seed_sql_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "application/sql"
  tags                   = merge(var.tags, { Purpose = "cdc-seed-sql-artifact" })
}

resource "aws_s3_object" "mutation_sql" {
  bucket                 = var.control_bucket_name
  key                    = "artifacts/sql/cdc_mutations.sql"
  source                 = var.mutation_sql_path
  source_hash            = filemd5(var.mutation_sql_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "application/sql"
  tags                   = merge(var.tags, { Purpose = "cdc-mutation-sql-artifact" })
}

resource "aws_cloudwatch_log_group" "cdc" {
  name              = "/aws-glue/jobs/${local.cdc_job_name}"
  retention_in_days = 30
  tags              = merge(var.tags, { Purpose = "cdc-glue-logs" })
}

resource "aws_cloudwatch_log_group" "seed" {
  name              = "/aws-glue/jobs/${local.seed_job_name}"
  retention_in_days = 30
  tags              = merge(var.tags, { Purpose = "cdc-seed-logs" })
}

resource "aws_iam_role" "glue" {
  name               = "${local.name}-glue-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "glue.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "cdc-glue-execution" })
}

resource "aws_iam_role_policy" "glue" {
  name = "cdc-iceberg-and-seed-access"
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = [local.landing_bucket_arn, local.lakehouse_bucket_arn, local.control_bucket_arn] },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = ["${local.landing_bucket_arn}/${local.dms_prefix}/*", "${local.control_bucket_arn}/*"] },
      { Effect = "Allow", Action = ["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = ["${local.lakehouse_bucket_arn}/*", "${local.control_bucket_arn}/*"] },
      { Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"], Resource = var.kms_key_arn },
      { Effect = "Allow", Action = ["glue:CreateTable", "glue:DeleteTable", "glue:GetDatabase", "glue:GetTable", "glue:GetTables", "glue:UpdateTable"], Resource = concat([local.glue_catalog_arn], local.glue_database_arns, local.glue_table_arns) },
      { Effect = "Allow", Action = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.source.arn },
      { Effect = "Allow", Action = ["ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcAttribute", "ec2:DescribeVpcEndpoints", "ec2:DescribeRouteTables"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = [aws_cloudwatch_log_group.cdc.arn, "${aws_cloudwatch_log_group.cdc.arn}:*", aws_cloudwatch_log_group.seed.arn, "${aws_cloudwatch_log_group.seed.arn}:*"] },
    ]
  })
}

resource "aws_glue_connection" "rds" {
  name            = "${local.name}-rds-connection"
  connection_type = "JDBC"
  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:postgresql://${aws_db_instance.source.address}:5432/${var.database_name}"
    SECRET_ID           = aws_secretsmanager_secret.source.arn
  }
  physical_connection_requirements {
    availability_zone      = data.aws_subnet.private.availability_zone
    subnet_id              = var.private_subnet_ids[0]
    security_group_id_list = [aws_security_group.glue.id]
  }
}

data "aws_subnet" "private" {
  id = var.private_subnet_ids[0]
}

resource "aws_glue_job" "cdc" {
  name              = local.cdc_job_name
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 15
  command {
    name            = "glueetl"
    script_location = "s3://${var.control_bucket_name}/artifacts/glue/glue_cdc_pipeline.py"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language"                     = "python"
    "--datalake-formats"                 = "iceberg"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.cdc.name
    "--CDC_PREFIX"                       = local.dms_prefix
    "--LANDING_BUCKET"                   = var.landing_bucket_name
    "--LAKEHOUSE_BUCKET"                 = var.lakehouse_bucket_name
    "--BRONZE_DATABASE"                  = var.glue_database_names["bronze"]
    "--SILVER_DATABASE"                  = var.glue_database_names["silver"]
    "--GOLD_DATABASE"                    = var.glue_database_names["gold"]
  }
  execution_property {
    max_concurrent_runs = 1
  }
  depends_on = [aws_s3_object.cdc_script, aws_cloudwatch_log_group.cdc]
  tags       = merge(var.tags, { Purpose = "cdc-iceberg-processing" })
}

resource "aws_glue_job" "seed" {
  name              = local.seed_job_name
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 15
  command {
    name            = "glueetl"
    script_location = "s3://${var.control_bucket_name}/artifacts/glue/glue_cdc_sql_bootstrap.py"
    python_version  = "3"
  }
  connections = [aws_glue_connection.rds.name]
  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.seed.name
    "--RDS_SECRET_ARN"                   = aws_secretsmanager_secret.source.arn
    "--RDS_JDBC_URL"                     = "jdbc:postgresql://${aws_db_instance.source.address}:5432/${var.database_name}"
    "--CONTROL_BUCKET"                   = var.control_bucket_name
    "--ACTION"                           = "schema_seed"
    "--SCHEMA_SQL_KEY"                   = aws_s3_object.schema_sql.key
    "--SEED_SQL_KEY"                     = aws_s3_object.seed_sql.key
    "--MUTATION_SQL_KEY"                 = aws_s3_object.mutation_sql.key
  }
  execution_property {
    max_concurrent_runs = 1
  }
  depends_on = [aws_s3_object.seed_script, aws_s3_object.schema_sql, aws_s3_object.seed_sql, aws_s3_object.mutation_sql, aws_glue_connection.rds, aws_vpc_endpoint.secrets_manager]
  tags       = merge(var.tags, { Purpose = "cdc-sql-bootstrap" })
}

resource "aws_iam_role" "step_functions" {
  name               = "${local.name}-step-functions-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "states.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "cdc-orchestration" })
}

resource "aws_iam_role_policy" "step_functions" {
  name = "start-and-monitor-cdc-glue"
  role = aws_iam_role.step_functions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["glue:BatchStopJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:StartJobRun"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"], Resource = "*" },
    ]
  })
}

resource "aws_sfn_state_machine" "cdc" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.step_functions.arn
  definition = jsonencode({
    Comment = "V1 DMS S3 CDC to Bronze/Silver/Gold Iceberg"
    StartAt = "RunCdcGlue"
    States = {
      RunCdcGlue = {
        Type       = "Task", Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = { JobName = aws_glue_job.cdc.name, Arguments = { "--CDC_OBJECT_KEY.$" = "$.detail.object.key", "--RUN_ID.$" = "$.id" } }
        End        = true
      }
    }
  })
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.cdc.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }
  depends_on = [aws_iam_role_policy.step_functions]
  tags       = merge(var.tags, { Purpose = "cdc-orchestration" })
}

resource "aws_iam_role" "eventbridge" {
  name               = "${local.name}-eventbridge-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "cdc-event-trigger" })
}

resource "aws_iam_role_policy" "eventbridge" {
  name   = "start-cdc-state-machine"
  role   = aws_iam_role.eventbridge.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "states:StartExecution", Resource = aws_sfn_state_machine.cdc.arn }] })
}

resource "aws_cloudwatch_event_rule" "cdc_object_created" {
  name           = "${local.name}-s3-object-created"
  description    = "Start CDC compaction after a DMS S3 object is created."
  event_bus_name = "default"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail      = { bucket = { name = [var.landing_bucket_name] }, object = { key = [{ prefix = "${local.dms_prefix}/" }] } }
  })
  tags = merge(var.tags, { Purpose = "cdc-event-trigger" })
}

resource "aws_cloudwatch_event_target" "cdc_state_machine" {
  rule      = aws_cloudwatch_event_rule.cdc_object_created.name
  target_id = "cdc-state-machine"
  arn       = aws_sfn_state_machine.cdc.arn
  role_arn  = aws_iam_role.eventbridge.arn
}
