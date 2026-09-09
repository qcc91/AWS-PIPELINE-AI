# V1 ML — Claim Fraud Batch Prediction

## Current runtime status

The SageMaker control-plane API is available in Sydney, and the V1 training,
validation, inference, and claim-ID fixtures are uploaded under the encrypted
control-bucket `ml/` prefix. Training did not start: the account-level quota
for `ml.m5.large` training usage is zero, and read-only quota discovery found
no nonzero SageMaker training-instance quota in the region. No training job or
training charge was created. Resume only after an appropriate training quota
is nonzero; do not cycle through instance types blindly.

The live Sydney account quotas are:

- `ml.m5.large for training job usage`: `L-611FA074`, current `0`, required `1`.
- `ml.m5.large for transform job usage`: `L-236AE59F`, current `0`, required `1`.

Both are adjustable account-level quotas and neither has a request in history.
All discovered SageMaker training-job instance quotas currently have value
zero, so there is no already-authorized low-cost instance substitution.

The Human Owner subsequently authorized non-billable quota requests. Requests
`b519d760dde9440687b17fbd2080ff62OTPDTvP7` (Training) and
`3b77277e7eba45ca8519f986852b485dtx2kZBLr` (Transform) were submitted for value
one on 2026-09-10. Both reached `CASE_OPENED`: Training case
`178899797700557`, Transform case `178899780000820`. No SageMaker compute was
created.

The V1 ML branch consumes the approved Gold `fact_claim` snapshot (or an
equivalent Athena export) and writes a reusable Gold `claim_risk` dataset.
Only on-demand SageMaker XGBoost Training and Batch Transform are used; no
real-time or persistent endpoint is provisioned.

## Flow

1. Terraform uploads the deterministic four-row fixture to the control bucket.
   Its fraud labels are synthetic heuristics for a runnable portfolio demo and
   must not be interpreted as measured fraud truth. For a meaningful model,
   replace them with an approved historical label set.
2. Export numeric features from Gold to `s3://.../ml/train/` and
   `validation/`. The CSV is headerless and label-first (`fraud_label`, then
   `claim_amount`, `approved_amount`, `days_to_submit`, `is_approved`). Keep a
   sidecar claim-id manifest for joining predictions.
3. Run `jobs/ml_claim_fraud_pipeline.py` with the DEV ML role and S3 URIs.
   The script resolves the AWS-published image using
   `sagemaker.image_uris.retrieve(framework="xgboost", region="ap-southeast-2", version="1.7-1")`.
   It does not contain a guessed or hard-coded regional image URI.
4. Wait for training, read the emitted `validation:auc` metric, require AUC >=
   0.50 for this tiny two-class V1 validation split,
   then create a SageMaker model from the completed artifact. After evaluation,
   register the approved model in the Terraform-created
   model package group, then submit Batch Transform against the feature input.
5. Run and wait for Batch Transform. Join probabilities to claim IDs and write `claim_risk` with
   `claim_id`, `fraud_probability` (`decimal(6,5)`), `risk_level`,
   `model_version`, `prediction_timestamp`, and `_run_id`.

The initial thresholds are implementation defaults (LOW < 0.30, MEDIUM <
0.70, HIGH >= 0.70) and require business/model evaluation approval before
being treated as production policy.

## Cost and security

`ml.m5.large`, one instance, and a 30-minute training cap are selected for the
small V1 dataset. Training and transform are charged only while running. The
SageMaker role is limited to Gold reads, ML/control writes, the platform KMS
key, and scoped CloudWatch metrics. No credentials or customer PII are logged.

Terraform resources for this branch were deployed under the approved V1
package. Runtime training remains blocked only by the account quota above.

## Reproducible run

`terraform plan` verifies the uploaded scripts/fixture and IAM resources. After
the approved DEV apply, invoke the pipeline CLI once with the train,
validation, inference, claim-ID sidecar, model-output, and transform-output S3
URIs. The CLI waits for every SageMaker and Glue stage and materializes rows
through the Glue Iceberg writer into
`insurance_dev_gold.claim_risk`; verify with Athena by checking one row per
`claim_id + model_version`, probabilities in `[0,1]`, and required columns.
