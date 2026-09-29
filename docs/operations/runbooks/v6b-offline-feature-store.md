# V6B Offline Feature Store

## Scope

The DEV claim-risk workload uses one Terraform-managed SageMaker Feature Group:

- name: `insurance-dev-claim-risk-features`
- record identifier: `claim_id`
- event time: `event_time` (the claim `submitted_at`; legacy prepared snapshots use their existing point-in-time `as_of_date` at midnight UTC)
- online store: disabled (no `online_store_config` is declared)
- offline store base: `s3://<control-bucket>/ml/feature-store`
- encryption: the existing customer-managed platform KMS key
- catalog: existing Glue database `insurance_dev_control`, table
  `claim_risk_features_offline`, managed by SageMaker Feature Store

The feature definitions are generated from `workloads/ml/claim_risk.py`. The
Feature Group therefore stores the exact numeric and one-hot columns consumed by
XGBoost, plus the existing label and Feature Store key fields. It does not run a
second feature-engineering implementation.

## Pipeline behavior

The managed DAG is:

```text
Gold / accepted prepared snapshot
  -> PrepareData (validate/split and PutRecord TargetStores=[OfflineStore])
  -> MaterializeFeatureStore (bounded Athena poll/readback)
  -> TrainXGBoost
  -> EvaluateModel
  -> ModelQualityGate
  -> RegisterModel -> CreateBatchModel -> BatchTransform -> PublishAndValidateGold
```

Feature Store writes are asynchronous. `MaterializeFeatureStore` waits up to 20
minutes for all `(claim_id, event_time)` keys to appear, chooses the newest write
for an idempotent repeated execution, and rebuilds train/validation/test/inference
channels in the original manifest order. A timeout fails before training. Training,
evaluation, and batch transform consume only these offline-store readback channels.

## Validation after an approved apply

Use the DEV operator role and record:

```powershell
aws sagemaker describe-feature-group `
  --feature-group-name insurance-dev-claim-risk-features `
  --region ap-southeast-2 `
  --profile aip-dev-ml-engineer
```

Confirm `FeatureGroupStatus=Created`, `OfflineStoreStatus.Status=Active`, the
resolved S3 URI and Glue table, and that `OnlineStoreConfig` is absent or disabled.
Accepted V6B execution `zr3k4aa3lzfz` submitted and materialized 120/120 records,
then trained from the offline-store readback. Its Gold validation passed with
120 rows, 120 unique claims and zero invalid probabilities.

Console path: **Amazon SageMaker AI console → Feature Store → Feature groups →
insurance-dev-claim-risk-features**. Inspect Details, Feature definitions, and
Offline store. The pipeline graph is at **Amazon SageMaker AI console → Pipelines →
insurance-dev-claim-risk → Executions**.

## Cost and cleanup

Offline Feature Store has no continuously running online store in this design.
Charges are usage-based S3 storage/requests, KMS requests, Athena bytes scanned,
and two transient `ml.m5.large` Processing jobs during a pipeline execution. The
new materialization job has a 25-minute hard runtime limit and normally waits no
more than the documented offline-store publication delay. For the 120-row DEV
proof, incremental storage and query cost should be negligible and the one-time
validation remains well below the authorized USD 5 ceiling; the Terraform plan
checkpoint must still use current regional prices before apply. There is no fixed
monthly Feature Store compute charge because Online Store is disabled.

Terraform destroy removes the Feature Group and its role. Offline Parquet objects
under the shared control bucket remain subject to the bucket's lifecycle/cleanup
policy and must not be broadly deleted by this runbook.

## Security notes

The Feature Store service role is limited to the Feature Store control-bucket
prefix, the existing KMS key, and the `insurance_dev_control` Glue namespace.
The Pipeline role can put/describe only this Feature Group and read its exact Glue
namespace through the existing encrypted Athena workgroup. No endpoint, notebook,
public access, long-lived key, PROD resource, or direct Human data permission is
introduced.
