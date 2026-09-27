# SageMaker Managed Claim-Risk Pipeline

Status: deployed with Human approval; end-to-end migration proof SUCCEEDED.

## Migration proof record (2026-09-27)

- Execution: `g46dxu0f1ydw`, display name `migration-accepted-snapshot`.
- PrepareData, TrainXGBoost, EvaluateModel, ModelQualityGate, RegisterModel,
  CreateBatchModel, BatchTransform and PublishAndValidateGold all succeeded.
- Final Pipeline status: `Succeeded`. Gold has 120 rows, 120 unique claim IDs,
  zero invalid probabilities. Athena validation:
  `938f0be5-bf34-4a36-8bbf-25748d872746`.
- Successful Glue publication:
  `jr_896f057455ef07a18471071f7e69cdc383742c14ca5fa8c37684656d1f5bbf48`.
- The two resumed steps reused successful upstream results; no retraining or
  repeated Batch Transform was required. No endpoint/notebook or persistent
  compute was introduced. Temporary job compute terminates with the jobs;
  model metadata, registry version and encrypted artifacts remain. Actual
  charges for failed/successful transient jobs have not been reconciled to billing.
- Test split: 24 rows; AUC 0.622222, accuracy 0.625, log loss 0.656316,
  precision/recall/F1 0 at the existing threshold, matching the accepted V1 run.
- Model package: `insurance-dev-claim-fraud/1`, pending manual model approval.
- Registration initially failed because SageMaker requests CreateModelPackageGroup
  even with the existing group. Added Create/Describe for that exact group only;
  RetryPipelineExecution is scoped to this pipeline's executions. Retried the
  same execution without rerunning successful Training/Processing jobs.
- The pre-V2 ID manifest has no `dataset_version`. Publication initially failed
  before writing Gold. A compatibility adapter adds a deterministic
  `legacy-manifest-sha256:` identifier to a separately encrypted runtime copy;
  source files, row order, IDs, dates, feature values and model inputs remain
  unchanged. This is lineage compatibility, not business-data remediation.
- Focused ML/security regression: 50 passed; Terraform validate and fmt passed.
- ML-scoped plan has one pre-existing legacy local-runner S3 asset path/hash
  update, not applied: `module.ml.aws_s3_object.pipeline_script`. The new managed
  pipeline and its runtime fixes have no further planned changes. This is not a
  claim that the whole DEV/bootstrap stack is drift-free.
- View in SageMaker Studio: Pipelines -> `insurance-dev-claim-risk` -> Executions
  -> `migration-accepted-snapshot`, then open the execution graph.
  [AWS viewing instructions](https://docs.aws.amazon.com/sagemaker/latest/dg/pipelines-studio-view-execution.html).

## Why this exists

The accepted V1 ML proof used real SageMaker Training and Batch Transform jobs,
but a workstation Python runner submitted and waited for each API operation.
The jobs were visible individually in AWS, while their dependencies were not a
persistent SageMaker Pipeline DAG. This enhancement moves orchestration into a
Terraform-managed `aws_sagemaker_pipeline` without adding an endpoint,
notebook, MWAA environment, Lambda function, or always-running compute.

## Managed DAG

```text
PrepareData (Processing + Athena Gold export)
  -> TrainXGBoost (Training)
  -> EvaluateModel (Processing, untouched chronological test split)
  -> ModelQualityGate (Condition on test AUC)
       -> FailQualityGate
       -> RegisterModel (PendingManualApproval)
          -> CreateBatchModel
          -> BatchTransform
          -> PublishAndValidateGold (Processing -> Glue -> Athena)
```

`PrepareData` queries `insurance_dev_gold.claim_risk_features` through the
existing encrypted Athena workgroup. It then applies the existing leakage-safe
feature contract and chronological 60/20/20 split. The legacy four-row
`fraud_label` fixture is not a Pipeline input.

For the Human-requested migration-only proof (2026-09-26), set the execution
parameter `PreparedInputUri` to
`s3://aip-insurance-dev-control-dev01/ml/runs/insurance-dev-claim-risk-v1-20260910-061552/input/`.
This reuses the six existing accepted prepared files unchanged instead of
re-exporting current Gold. It verifies managed orchestration, not current data
quality. Leave the parameter empty to use the Athena path. Current HOME rows
have non-applicable vehicle fields rejected by the existing strict preprocessing;
that data/validation issue is explicitly deferred, not silently fixed.

The evaluation step calculates metrics on the untouched test split. Only a run
meeting `MinimumAuc` may register a model, score the complete input and publish
`insurance_dev_gold.claim_risk`. The registered version starts as
`PendingManualApproval`; this does not create a real-time deployment.

## Terraform and runtime boundary

Terraform owns the Pipeline definition, its exact execution role policy, code
assets, Model Package Group, Lake Formation grants and metadata outputs. A
Pipeline execution remains an ephemeral runtime operation and must not be
recorded as a Terraform resource. It can be started from the SageMaker console
or the `StartPipelineExecution` API after deployment approval.

The Pipeline is designed to appear in the SageMaker Pipelines console as
`insurance-dev-claim-risk`. Its steps, executions, parameters and graph are
therefore visible as one managed ML workflow. `ProjectUserTag*` tags are
included for Unified Studio compatibility, but display inside a particular
Unified Studio project still depends on that project's profile and permissions.

This is the only material "individual AWS jobs exist but the end-to-end
workflow is not an AWS-managed, UI-visible pipeline" gap found in the V5
platform review. Batch and CDC already use persistent EventBridge, Step
Functions and Glue resources; RAG already uses a Bedrock Knowledge Base and S3
Vectors; CI/CD already uses GitHub Actions, CodePipeline and CodeBuild. Two
intentional exceptions remain: Glue Data Quality executes real DQDL inline
rather than storing separate named Ruleset resources, and QuickSight remains
disabled because the FREE account has no approved subscription.

## Security and cost

- The execution role reads only approved Gold features and ML/control prefixes.
- Lake Formation grants only `claim_risk_features` and `claim_risk` to the
  SageMaker workload role.
- Model, processing and transform outputs use the existing platform KMS key.
- TerraformExecution receives Pipeline administration only for the exact
  `insurance-dev-claim-risk` ARN; it does not gain broad SageMaker authority.
- No endpoint or persistent compute is created. The Pipeline definition itself
  does not run compute; executions create short-lived Processing, Training and
  Transform jobs.
- A real run uses three short Processing jobs, one `ml.m5.large` Training job,
  one `ml.m5.large` Transform job and the existing Glue postprocess job. Account
  Processing/Training/Transform quotas must be checked before execution.
- SageMaker Pipelines has no separate orchestration charge; each execution is
  charged only for its short-lived Processing, Training, Batch Transform,
  Glue, Athena, S3 and KMS usage. There is no new fixed monthly compute cost.

## Reviewed DEV plans

- Separately managed bootstrap: `0 add / 1 in-place change / 0 destroy`. This
  grants TerraformExecution exact Pipeline administration, control-bucket ML
  artifact upload and read-only Service Quotas discovery. Because
  TerraformExecution must not administer its own bootstrap policy, apply needs
  the existing one-time root/bootstrap path. Reviewed binary plan SHA256:
  `f84cc6751d45c5a46330eb332e63f1c2dcfae44d811ef1ab24f67a8edeeff6ae`.
- Targeted DEV foundation: `11 add / 3 in-place change / 0 destroy / 0 replace`.
  The changes are the managed Pipeline, four code objects, six Lake Formation
  grants/opt-ins, the SageMaker workload policy, the MLEngineer Pipeline UI/run
  policy and the existing Glue postprocess object at its post-refactor source
  path. Reviewed binary plan SHA256:
  `31c14541b8cc272967d250a4bc82dba144c073ab609d62c5976a0f6a9eb053ec`.

The targeted plan intentionally excludes unrelated post-refactor path drift in
the wider DEV root. A full untargeted plan must be reconciled separately; it is
not part of this ML enhancement.

The bootstrap role policy update and the DEV foundation change require their
normal reviewed Terraform apply sequence. No apply or Pipeline execution is
authorized merely by this document.
