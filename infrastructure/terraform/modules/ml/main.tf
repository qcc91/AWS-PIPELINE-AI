locals {
  lakehouse_arn = "arn:aws:s3:::${var.lakehouse_bucket_name}"
  control_arn   = "arn:aws:s3:::${var.control_bucket_name}"
}

resource "aws_s3_object" "pipeline_script" {
  bucket                 = var.control_bucket_name
  key                    = "artifacts/ml/ml_claim_fraud_pipeline.py"
  source                 = var.pipeline_script_path
  source_hash            = filemd5(var.pipeline_script_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "text/x-python"
}

resource "aws_s3_object" "training_data" {
  bucket                 = var.control_bucket_name
  key                    = "ml/input/ml_claim_training.csv"
  source                 = var.training_data_path
  source_hash            = filemd5(var.training_data_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "text/csv"
}

resource "aws_s3_object" "postprocess_script" {
  bucket                 = var.control_bucket_name
  key                    = "artifacts/ml/glue_claim_risk_postprocess.py"
  source                 = var.postprocess_script_path
  source_hash            = filemd5(var.postprocess_script_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
}

resource "aws_s3_object" "pipeline_asset" {
  for_each = {
    "sagemaker_pipeline_prepare.py"  = var.pipeline_prepare_script_path
    "sagemaker_pipeline_evaluate.py" = var.pipeline_evaluate_script_path
    "sagemaker_pipeline_publish.py"  = var.pipeline_publish_script_path
    "claim_risk.py"                  = var.claim_risk_library_path
  }

  bucket                 = var.control_bucket_name
  key                    = "artifacts/ml/pipeline/${each.key}"
  source                 = each.value
  source_hash            = filemd5(each.value)
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content_type           = "text/x-python"
}

resource "aws_iam_role" "postprocess" {
  name               = "insurance-${var.environment}-claim-risk-glue-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "glue.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Purpose = "claim-risk-iceberg-postprocess" })
}

resource "aws_iam_role_policy" "postprocess" {
  name = "claim-risk-iceberg-read-write"
  role = aws_iam_role.postprocess.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = [local.lakehouse_arn, local.control_arn] },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${local.control_arn}/artifacts/ml/*"] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${local.lakehouse_arn}/lakehouse/*", "${local.control_arn}/ml/*"] },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"], Resource = var.kms_key_arn },
    { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:CreateTable", "glue:UpdateTable"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" }
  ] })
}

resource "aws_glue_job" "postprocess" {
  name              = "insurance-${var.environment}-claim-risk-postprocess"
  role_arn          = aws_iam_role.postprocess.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.control_bucket_name}/${aws_s3_object.postprocess_script.key}"
  }
  default_arguments = { "--job-language" = "python", "--datalake-formats" = "iceberg", "--TempDir" = "s3://${var.control_bucket_name}/glue-temp/", "--conf" = "spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO --conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.lakehouse_bucket_name}/lakehouse/" }
  depends_on        = [aws_s3_object.postprocess_script, aws_iam_role_policy.postprocess]
  tags              = merge(var.tags, { Purpose = "claim-risk-iceberg-postprocess" })
}

resource "aws_cloudwatch_log_group" "training" {
  name              = "/aws/sagemaker/insurance-${var.environment}-claim-fraud"
  retention_in_days = 30
  tags              = merge(var.tags, { Purpose = "ml-training-and-batch" })
}

resource "aws_iam_role" "sagemaker" {
  name = "insurance-${var.environment}-claim-fraud-sagemaker-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "sagemaker.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = merge(var.tags, { Purpose = "claim-fraud-ml" })
}

resource "aws_iam_role_policy" "sagemaker" {
  name = "claim-fraud-gold-training-and-risk-output"
  role = aws_iam_role.sagemaker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = [local.lakehouse_arn, local.control_arn] },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = ["${local.lakehouse_arn}/lakehouse/gold/*", "${local.control_arn}/ml/*"] },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = ["${local.control_arn}/artifacts/ml/pipeline/*"] },
      { Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"], Resource = var.kms_key_arn },
      { Effect = "Allow", Action = "kms:CreateGrant", Resource = var.kms_key_arn, Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } } },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = ["arn:aws:ecr:${var.aws_region}:*:repository/sagemaker-xgboost*", "arn:aws:ecr:${var.aws_region}:*:repository/sagemaker-scikit-learn*"] },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*", Condition = { StringEquals = { "cloudwatch:namespace" = "Insurance/ML" } } },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"], Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/sagemaker/*" },
      { Effect = "Allow", Action = ["sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob", "sagemaker:CreateTrainingJob", "sagemaker:DescribeTrainingJob", "sagemaker:StopTrainingJob", "sagemaker:CreateModel", "sagemaker:DescribeModel", "sagemaker:DeleteModel", "sagemaker:CreateTransformJob", "sagemaker:DescribeTransformJob", "sagemaker:StopTransformJob", "sagemaker:AddTags", "sagemaker:ListTags"], Resource = ["arn:aws:sagemaker:${var.aws_region}:${var.account_id}:processing-job/pipelines-*", "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:training-job/pipelines-*", "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:model/pipelines-*", "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:transform-job/pipelines-*"] },
      { Effect = "Allow", Action = ["sagemaker:CreateModelPackage", "sagemaker:DescribeModelPackage", "sagemaker:ListTags", "sagemaker:AddTags"], Resource = [aws_sagemaker_model_package_group.claim_fraud.arn, "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:model-package/${aws_sagemaker_model_package_group.claim_fraud.model_package_group_name}/*"] },
      { Effect = "Allow", Action = "iam:PassRole", Resource = aws_iam_role.sagemaker.arn, Condition = { StringEquals = { "iam:PassedToService" = "sagemaker.amazonaws.com" } } },
      { Effect = "Allow", Action = ["glue:StartJobRun", "glue:GetJobRun"], Resource = aws_glue_job.postprocess.arn },
      { Effect = "Allow", Action = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults"], Resource = "arn:aws:athena:${var.aws_region}:${var.account_id}:workgroup/${var.athena_workgroup_name}" },
      { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:GetPartitions"], Resource = ["arn:aws:glue:${var.aws_region}:${var.account_id}:catalog", "arn:aws:glue:${var.aws_region}:${var.account_id}:database/${var.gold_database_name}", "arn:aws:glue:${var.aws_region}:${var.account_id}:table/${var.gold_database_name}/claim_risk_features", "arn:aws:glue:${var.aws_region}:${var.account_id}:table/${var.gold_database_name}/claim_risk"] },
      { Effect = "Allow", Action = "lakeformation:GetDataAccess", Resource = "*" }
    ]
  })
}

resource "aws_sagemaker_model_package_group" "claim_fraud" {
  model_package_group_name        = "insurance-${var.environment}-claim-fraud"
  model_package_group_description = "Versioned XGBoost claim fraud models; registration is performed after evaluation."
  tags                            = merge(var.tags, { Purpose = "claim-fraud-model-registry" })
}
