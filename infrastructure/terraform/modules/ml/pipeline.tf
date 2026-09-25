locals {
  pipeline_name     = "insurance-${var.environment}-claim-risk"
  pipeline_code_uri = "s3://${var.control_bucket_name}/artifacts/ml/pipeline"
  pipeline_base_uri = "s3://${var.control_bucket_name}/ml/pipeline"

  processing_resources = {
    ClusterConfig = {
      InstanceCount  = 1
      InstanceType   = "ml.m5.large"
      VolumeSizeInGB = 20
      VolumeKmsKeyId = var.kms_key_arn
    }
  }

  code_input = {
    InputName = "code"
    S3Input = {
      S3Uri                  = local.pipeline_code_uri
      LocalPath              = "/opt/ml/processing/code"
      S3DataType             = "S3Prefix"
      S3InputMode            = "File"
      S3DataDistributionType = "FullyReplicated"
      S3CompressionType      = "None"
    }
  }

  pipeline_definition = {
    Version = "2020-12-01"
    Metadata = {
      Purpose = "Leakage-safe claim risk training and batch publication"
    }
    Parameters = [
      {
        Name         = "OutputPrefix"
        Type         = "String"
        DefaultValue = local.pipeline_base_uri
      },
      {
        Name         = "MinimumAuc"
        Type         = "Float"
        DefaultValue = 0.50
      },
    ]
    PipelineExperimentConfig = {
      ExperimentName = { Get = "Execution.PipelineName" }
      TrialName      = { Get = "Execution.PipelineExecutionId" }
    }
    Steps = [
      {
        Name = "PrepareData"
        Type = "Processing"
        Arguments = {
          AppSpecification = {
            ImageUri            = var.processing_image_uri
            ContainerEntrypoint = ["python3"]
            ContainerArguments = [
              "/opt/ml/processing/code/sagemaker_pipeline_prepare.py",
              "--region", var.aws_region,
              "--athena-workgroup", var.athena_workgroup_name,
              "--gold-database", var.gold_database_name,
              "--athena-output-uri", { "Std:Join" = { On = "/", Values = [{ Get = "Parameters.OutputPrefix" }, "executions", { Get = "Execution.PipelineExecutionId" }, "athena-prepare"] } },
            ]
          }
          ProcessingInputs = [local.code_input]
          ProcessingOutputConfig = {
            KmsKeyId = var.kms_key_arn
            Outputs = [
              for output in ["train", "validation", "test", "inference", "manifest", "metadata"] : {
                OutputName = output
                S3Output = {
                  LocalPath = "/opt/ml/processing/${output}"
                  S3Uri = {
                    "Std:Join" = {
                      On     = "/"
                      Values = [{ Get = "Parameters.OutputPrefix" }, "executions", { Get = "Execution.PipelineExecutionId" }, "prepared", output]
                    }
                  }
                  S3UploadMode = "EndOfJob"
                }
              }
            ]
          }
          ProcessingResources = local.processing_resources
          RoleArn             = aws_iam_role.sagemaker.arn
          StoppingCondition   = { MaxRuntimeInSeconds = 900 }
        }
      },
      {
        Name      = "TrainXGBoost"
        Type      = "Training"
        DependsOn = ["PrepareData"]
        Arguments = {
          AlgorithmSpecification = {
            TrainingImage     = var.xgboost_image_uri
            TrainingInputMode = "File"
          }
          HyperParameters = {
            objective             = "binary:logistic"
            eval_metric           = "auc"
            num_round             = "100"
            max_depth             = "3"
            eta                   = "0.08"
            min_child_weight      = "2"
            subsample             = "0.80"
            colsample_bytree      = "0.80"
            seed                  = "42"
            early_stopping_rounds = "12"
          }
          InputDataConfig = [
            {
              ChannelName = "train"
              ContentType = "text/csv"
              InputMode   = "File"
              DataSource = { S3DataSource = {
                S3DataType             = "S3Prefix"
                S3Uri                  = { Get = "Steps.PrepareData.ProcessingOutputConfig.Outputs['train'].S3Output.S3Uri" }
                S3DataDistributionType = "FullyReplicated"
              } }
            },
            {
              ChannelName = "validation"
              ContentType = "text/csv"
              InputMode   = "File"
              DataSource = { S3DataSource = {
                S3DataType             = "S3Prefix"
                S3Uri                  = { Get = "Steps.PrepareData.ProcessingOutputConfig.Outputs['validation'].S3Output.S3Uri" }
                S3DataDistributionType = "FullyReplicated"
              } }
            },
          ]
          OutputDataConfig = {
            KmsKeyId     = var.kms_key_arn
            S3OutputPath = { "Std:Join" = { On = "/", Values = [{ Get = "Parameters.OutputPrefix" }, "executions", { Get = "Execution.PipelineExecutionId" }, "model"] } }
          }
          ResourceConfig = {
            InstanceCount  = 1
            InstanceType   = "ml.m5.large"
            VolumeSizeInGB = 30
            VolumeKmsKeyId = var.kms_key_arn
          }
          RoleArn           = aws_iam_role.sagemaker.arn
          StoppingCondition = { MaxRuntimeInSeconds = 1800 }
        }
      },
      {
        Name      = "EvaluateModel"
        Type      = "Processing"
        DependsOn = ["TrainXGBoost"]
        PropertyFiles = [{
          Name       = "EvaluationReport"
          OutputName = "evaluation"
          FilePath   = "evaluation.json"
        }]
        Arguments = {
          AppSpecification = {
            ImageUri            = var.xgboost_image_uri
            ContainerEntrypoint = ["python3"]
            ContainerArguments  = ["/opt/ml/processing/code/sagemaker_pipeline_evaluate.py"]
          }
          ProcessingInputs = [
            local.code_input,
            {
              InputName = "model"
              S3Input = {
                S3Uri                  = { Get = "Steps.TrainXGBoost.ModelArtifacts.S3ModelArtifacts" }
                LocalPath              = "/opt/ml/processing/model"
                S3DataType             = "S3Prefix"
                S3InputMode            = "File"
                S3DataDistributionType = "FullyReplicated"
                S3CompressionType      = "None"
              }
            },
            {
              InputName = "test"
              S3Input = {
                S3Uri                  = { Get = "Steps.PrepareData.ProcessingOutputConfig.Outputs['test'].S3Output.S3Uri" }
                LocalPath              = "/opt/ml/processing/test"
                S3DataType             = "S3Prefix"
                S3InputMode            = "File"
                S3DataDistributionType = "FullyReplicated"
                S3CompressionType      = "None"
              }
            },
          ]
          ProcessingOutputConfig = {
            KmsKeyId = var.kms_key_arn
            Outputs = [{
              OutputName = "evaluation"
              S3Output = {
                LocalPath = "/opt/ml/processing/evaluation"
                S3Uri = { "Std:Join" = {
                  On     = "/"
                  Values = [{ Get = "Parameters.OutputPrefix" }, "executions", { Get = "Execution.PipelineExecutionId" }, "evaluation"]
                } }
                S3UploadMode = "EndOfJob"
              }
            }]
          }
          ProcessingResources = local.processing_resources
          RoleArn             = aws_iam_role.sagemaker.arn
          StoppingCondition   = { MaxRuntimeInSeconds = 900 }
        }
      },
      {
        Name = "ModelQualityGate"
        Type = "Condition"
        Arguments = {
          Conditions = [{
            Type = "GreaterThanOrEqualTo"
            LeftValue = { "Std:JsonGet" = {
              PropertyFile = { Get = "Steps.EvaluateModel.PropertyFiles['EvaluationReport']" }
              Path         = "binary_classification_metrics.auc.value"
            } }
            RightValue = { Get = "Parameters.MinimumAuc" }
          }]
          IfSteps = [
            {
              Name = "RegisterModel"
              Type = "RegisterModel"
              Arguments = {
                ModelPackageGroupName = aws_sagemaker_model_package_group.claim_fraud.model_package_group_name
                ModelApprovalStatus   = "PendingManualApproval"
                InferenceSpecification = {
                  Containers = [{
                    Image        = var.xgboost_image_uri
                    ModelDataUrl = { Get = "Steps.TrainXGBoost.ModelArtifacts.S3ModelArtifacts" }
                  }]
                  SupportedContentTypes      = ["text/csv"]
                  SupportedResponseMIMETypes = ["text/csv"]
                }
                ModelMetrics = {
                  ModelQuality = {
                    Statistics = {
                      ContentType = "application/json"
                      S3Uri = { "Std:Join" = {
                        On     = "/"
                        Values = [{ Get = "Steps.EvaluateModel.ProcessingOutputConfig.Outputs['evaluation'].S3Output.S3Uri" }, "evaluation.json"]
                      } }
                    }
                  }
                }
              }
            },
            {
              Name      = "CreateBatchModel"
              Type      = "CreateModel"
              DependsOn = ["RegisterModel"]
              Arguments = {
                ExecutionRoleArn = aws_iam_role.sagemaker.arn
                PrimaryContainer = {
                  Image        = var.xgboost_image_uri
                  ModelDataUrl = { Get = "Steps.TrainXGBoost.ModelArtifacts.S3ModelArtifacts" }
                }
              }
            },
            {
              Name      = "BatchTransform"
              Type      = "Transform"
              DependsOn = ["CreateBatchModel"]
              Arguments = {
                ModelName = { Get = "Steps.CreateBatchModel.ModelName" }
                TransformInput = {
                  ContentType = "text/csv"
                  SplitType   = "Line"
                  DataSource = { S3DataSource = {
                    S3DataType = "S3Prefix"
                    S3Uri      = { Get = "Steps.PrepareData.ProcessingOutputConfig.Outputs['inference'].S3Output.S3Uri" }
                  } }
                }
                TransformOutput = {
                  AssembleWith = "Line"
                  KmsKeyId     = var.kms_key_arn
                  S3OutputPath = { "Std:Join" = {
                    On     = "/"
                    Values = [{ Get = "Parameters.OutputPrefix" }, "executions", { Get = "Execution.PipelineExecutionId" }, "predictions"]
                  } }
                }
                TransformResources = {
                  InstanceCount = 1
                  InstanceType  = "ml.m5.large"
                }
              }
            },
            {
              Name      = "PublishAndValidateGold"
              Type      = "Processing"
              DependsOn = ["BatchTransform"]
              PropertyFiles = [{
                Name       = "GoldValidation"
                OutputName = "validation"
                FilePath   = "validation.json"
              }]
              Arguments = {
                AppSpecification = {
                  ImageUri            = var.processing_image_uri
                  ContainerEntrypoint = ["python3"]
                  ContainerArguments = [
                    "/opt/ml/processing/code/sagemaker_pipeline_publish.py",
                    "--region", var.aws_region,
                    "--glue-job-name", aws_glue_job.postprocess.name,
                    "--transform-output-uri", { Get = "Steps.BatchTransform.TransformOutput.S3OutputPath" },
                    "--claim-ids-uri", { Get = "Steps.PrepareData.ProcessingOutputConfig.Outputs['manifest'].S3Output.S3Uri" },
                    "--gold-database", var.gold_database_name,
                    "--model-version", { Get = "Steps.RegisterModel.ModelPackageArn" },
                    "--run-id", { Get = "Execution.PipelineExecutionId" },
                    "--athena-workgroup", var.athena_workgroup_name,
                    "--athena-output-uri", { "Std:Join" = { On = "/", Values = [{ Get = "Parameters.OutputPrefix" }, "executions", { Get = "Execution.PipelineExecutionId" }, "athena"] } },
                  ]
                }
                ProcessingInputs = [local.code_input]
                ProcessingOutputConfig = {
                  KmsKeyId = var.kms_key_arn
                  Outputs = [{
                    OutputName = "validation"
                    S3Output = {
                      LocalPath = "/opt/ml/processing/validation"
                      S3Uri = { "Std:Join" = {
                        On     = "/"
                        Values = [{ Get = "Parameters.OutputPrefix" }, "executions", { Get = "Execution.PipelineExecutionId" }, "gold-validation"]
                      } }
                      S3UploadMode = "EndOfJob"
                    }
                  }]
                }
                ProcessingResources = local.processing_resources
                RoleArn             = aws_iam_role.sagemaker.arn
                StoppingCondition   = { MaxRuntimeInSeconds = 1200 }
              }
            },
          ]
          ElseSteps = [{
            Name = "FailQualityGate"
            Type = "Fail"
            Arguments = {
              ErrorMessage = "Independent chronological test AUC is below MinimumAuc; model was not registered or published."
            }
          }]
        }
      },
    ]
  }
}

resource "aws_sagemaker_pipeline" "claim_risk" {
  pipeline_name         = local.pipeline_name
  pipeline_display_name = "Insurance-${upper(var.environment)}-Claim-Risk"
  pipeline_description  = "Prepare, train, evaluate, register, batch-score, publish and validate claim risk."
  role_arn              = aws_iam_role.sagemaker.arn
  pipeline_definition   = jsonencode(local.pipeline_definition)
  tags = merge(var.tags, {
    Purpose                 = "claim-risk-managed-ml-pipeline"
    ProjectUserTagManagedBy = "Terraform"
    ProjectUserTagWorkload  = "insurance-claim-risk"
  })

  depends_on = [
    aws_iam_role_policy.sagemaker,
    aws_s3_object.pipeline_asset,
    aws_sagemaker_model_package_group.claim_fraud,
  ]
}
