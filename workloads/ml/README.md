# Claim-risk managed ML workflow

The claim-risk workload consumes the accepted Gold `claim_risk_features`
contract and runs as a native Amazon SageMaker Pipeline. The managed graph is:

```text
PrepareData -> TrainXGBoost -> EvaluateModel -> ModelQualityGate
                                                   | pass
                                                   v
                                            RegisterModel
                                                   |
                                            CreateBatchModel
                                                   |
                                            BatchTransform
                                                   |
                                       PublishAndValidateGold
```

`pipeline/pipeline_definition.py` owns the workflow semantics. It emits the
dependency-free SageMaker service JSON used by Terraform, so `terraform plan`
does not need the SageMaker SDK. Terraform owns the durable control plane: the
Pipeline resource, execution role, Model Package Group, encrypted S3 objects,
KMS permissions and the Glue publication job. Environment-specific ARNs, names
and image URIs are passed from Terraform to the Python definition.

The processing entry points reuse the existing implementation:

- `sagemaker_pipeline_prepare.py` exports Gold data or reuses an explicitly
  supplied accepted prepared snapshot, then writes deterministic splits.
- `sagemaker_pipeline_evaluate.py` evaluates the untouched test split and
  writes `evaluation.json`.
- `sagemaker_pipeline_publish.py` invokes the existing Glue post-processing
  job and validates the Gold `claim_risk` result through Athena.

Models that meet `MinimumAuc` are registered as `PendingManualApproval` before
batch inference. The workload creates no notebook instance, real-time endpoint
or automated production promotion. DEV executions use short-lived
`ml.m5.large` Processing, Training and Batch Transform jobs.

The Terraform registration is in
`infrastructure/terraform/modules/ml/pipeline.tf`. The registered pipeline name
remains `insurance-<environment>-claim-risk`.

For DEV, use the standard SageMaker AI Pipelines UI:

`https://console.aws.amazon.com/sagemaker/home?region=ap-southeast-2#/pipelines/insurance-dev-claim-risk`

The current IAM-based Unified Studio project's MLflow page is a different
surface and does not list native SageMaker Pipelines. The Pipeline is tagged
with `AmazonDataZoneProject=d1zzpm6mte659e` for project association, but the
standard Pipelines UI is the supported V6 inspection path.

