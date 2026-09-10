# V1 ML — Claim Risk Batch Prediction

## Shared-data design transition

The approved business target is now `high_risk_claim` at claim-submission time,
with output `high_risk_probability`. Training features must be derived from the
shared customer/policy/product/broker/claim/payment histories defined in
`architecture/data-model.md`, using point-in-time cutoffs. The existing tiny
`fraud_label` fixture and fraud-named script/resource identifiers are retained
only as an earlier technical smoke-test artifact; they are not accepted as the
final V1 analytical training dataset and must not be executed as final ML proof.
No deployed resource is renamed by this documentation-only update.

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

Both are adjustable account-level quotas. At initial discovery neither had a
request in history. All discovered SageMaker training-job instance quotas
currently have value zero, so there is no already-authorized low-cost instance
substitution.

The Human Owner subsequently authorized non-billable quota requests. Requests
`b519d760dde9440687b17fbd2080ff62OTPDTvP7` (Training) and
`3b77277e7eba45ca8519f986852b485dtx2kZBLr` (Transform) were submitted for value
one on 2026-09-10. Both reached `CASE_OPENED`: Training case
`178899797700557`, Transform case `178899780000820`. No SageMaker compute was
created.

The V1 ML branch consumes point-in-time feature datasets derived from approved
Silver/Gold business data and writes a reusable Gold `claim_risk` dataset.
Only on-demand SageMaker XGBoost Training and Batch Transform are used; no
real-time or persistent endpoint is provisioned.

## Flow

1. Generate reproducible shared business entities and future claim outcomes
   with controlled multi-variable correlations and noise. The target balance
   should be about 20%–35% positive, not a single-field deterministic rule.
2. At each claim `submitted_at`, materialize point-in-time customer, policy,
   product, broker, payment, and prior-claim features. Export headerless,
   label-first training/validation CSV with `high_risk_claim`; exclude
   `approved_amount`, `paid_amount`, final status/severity, settlement duration,
   and all other post-outcome fields. `claim_amount` and reporting delay may be
   used because they are known at submission. Keep a sidecar claim-ID manifest
   for joining predictions.
3. Update and run the existing SageMaker pipeline runner with the DEV ML role
   and accepted shared-data S3 URIs. The current file name is a legacy internal
   identifier, not the business target.
   The script resolves the AWS-published image using
   `sagemaker.image_uris.retrieve(framework="xgboost", region="ap-southeast-2", version="1.7-1")`.
   It does not contain a guessed or hard-coded regional image URI.
4. Wait for training, read the emitted `validation:auc` metric, require AUC >=
   0.50 for this tiny two-class V1 validation split,
   then create a SageMaker model from the completed artifact. After evaluation,
   register the approved model in the Terraform-created
   model package group, then submit Batch Transform against the feature input.
5. Run and wait for Batch Transform. Join probabilities to claim IDs and write `claim_risk` with
   `claim_id`, `high_risk_probability` (`decimal(6,5)`), `risk_level`,
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
package. Runtime training remains blocked by the account quota, and final V1
execution additionally requires the documented shared-data fixture/runner
alignment. That implementation is not part of this documentation-only update.

## Reproducible run

`terraform plan` verifies the uploaded scripts/fixture and IAM resources. After
the approved DEV apply, invoke the pipeline CLI once with the train,
validation, inference, claim-ID sidecar, model-output, and transform-output S3
URIs. The CLI waits for every SageMaker and Glue stage and materializes rows
through the Glue Iceberg writer into
`insurance_dev_gold.claim_risk`; verify with Athena by checking one row per
`claim_id + model_version`, probabilities in `[0,1]`, and required columns.

## File-derived feature readiness

The V1 file-source expansion completed in DEV on 2026-09-10. It did not run
SageMaker while the two quota requests remain pending. Its 120-row
`claim_risk_features` Iceberg table passed cross-source completeness,
feature-column quality, and point-in-time checks in Athena.

Implemented file-derived inputs are product type/risk tier, broker tier, regional
accident/theft/weather/natural-hazard scores, vehicle risk and repair-cost
bands, safety rating, and coverage tier/limit/excess. Product records require
effective-date/as-of selection at claim `submitted_at`; broker, region, vehicle,
and coverage reference snapshots must have been published by that time.
Historical broker/product loss ratios and claim rates
must be calculated only from facts visible before the prediction timestamp.

The current OLTP schema is unchanged. The broker-claim file carries existing
OLTP policy/customer keys and explicit broker/claim-type/region/vehicle/
coverage reference keys; product enrichment uses the OLTP policy product ID.
The file claim is an external Batch fact and does not replace the PostgreSQL
claim source. This lineage must remain visible in feature interpretation.
