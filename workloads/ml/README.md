# Claim-risk managed ML workflow

The claim-risk workload consumes the accepted Gold `claim_risk_features`
contract and runs as a native Amazon SageMaker Pipeline. The managed graph is:

```text
PrepareData -> MaterializeFeatureStore -> TrainXGBoost -> EvaluateModel
                                                            |
                                                     ModelQualityGate
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
  supplied accepted prepared snapshot, writes deterministic splits, and writes
  the exact XGBoost feature contract to the offline Feature Group.
- `sagemaker_pipeline_materialize_feature_store.py` performs a bounded Athena
  readback from the offline Feature Store and rebuilds the training channels;
  Training never consumes the pre-write files directly.
- `sagemaker_pipeline_evaluate.py` evaluates the untouched test split and
  writes `evaluation.json`.
- `sagemaker_pipeline_publish.py` invokes the existing Glue post-processing
  job and validates the Gold `claim_risk` result through Athena.

Models that meet `MinimumAuc` are registered as `PendingManualApproval` before
batch inference. The workload creates no notebook instance, real-time endpoint
or automated production promotion. DEV executions use short-lived
`ml.m5.large` Processing, Training and Batch Transform jobs.

Service responsibilities are deliberately separate:

- SageMaker Pipeline owns end-to-end orchestration and the UI-visible DAG.
- Offline Feature Store owns durable feature materialization and readback; no
  online serving store is enabled.
- Model Registry owns model-version and approval-state governance.
- Batch Transform performs inference without a persistent endpoint.
- Managed MLflow records experiment parameters, metrics, artifacts and lineage;
  it is not a second orchestrator and remains stopped when not in use.

The Terraform registration is in
`infrastructure/terraform/modules/ml/pipeline.tf`. The registered pipeline name
remains `insurance-<environment>-claim-risk`.

For DEV, use the standard SageMaker AI Pipelines UI:

`https://console.aws.amazon.com/sagemaker/home?region=ap-southeast-2#/pipelines/insurance-dev-claim-risk`

The current IAM-based Unified Studio project's MLflow page is a different
surface and does not list native SageMaker Pipelines. The Pipeline is tagged
with `AmazonDataZoneProject=d1zzpm6mte659e` for project association, but the
standard Pipelines UI is the supported V6 inspection path.

## MLflow evidence backfill

`log_existing_pipeline_run_to_mlflow.py` adds experiment tracking without
changing or rerunning the managed DAG. It resolves an already successful
Pipeline execution through SageMaker APIs, reads only its small
`evaluation.json`, feature `metadata.json`, and Gold `validation.json`
artifacts, and logs the following to the `insurance-claim-risk` experiment:

- the actual XGBoost Training-job hyperparameters;
- the actual evaluation metrics (AUC, log loss, accuracy, precision, recall,
  F1, and evaluation row count when present);
- Pipeline name/execution ID, prepared Gold input reference, dataset version,
  model artifact URI, Model Package ARN, and an explicit source Git SHA;
- the three existing JSON reports plus one small generated lineage document.

The model archive and source datasets are referenced but deliberately not
copied into MLflow. Repeating the command reuses an existing finished MLflow
Run tagged with the same Pipeline execution ID.

Install `sagemaker-mlflow` and the MLflow client version that matches the
tracking server. AWS currently maps server 3.0.x to `mlflow==3.0.0`, 2.16.x to
`mlflow==2.16.2`, and 2.13.x to `mlflow==2.13.2`. Then run, using an identity
authorized for the exact tracking server and existing Pipeline evidence:

```powershell
python workloads/ml/log_existing_pipeline_run_to_mlflow.py `
  --tracking-server-arn <tracking-server-arn> `
  --pipeline-execution-id g46dxu0f1ydw `
  --source-git-sha 81d45cd25b449336ef62b59b82f5e18e603ae1ac `
  --profile aip-dev-ml-engineer
```

The command refuses to log a non-succeeded Pipeline execution and never calls
an API that starts Training, Processing, Transform, a Pipeline execution, or an
endpoint.

