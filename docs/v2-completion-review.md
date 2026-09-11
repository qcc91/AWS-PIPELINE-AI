# V2 Consolidated Completion Review

Date: 2026-09-12

Region: `ap-southeast-2`

Environment: DEV
Status: V2 ACCEPTANCE AMENDMENT COMPLETE — awaiting Human acceptance

## Architecture

V2 retains two structured ingestion patterns—Batch/File and PostgreSQL
full-load+CDC—feeding one shared S3 + Iceberg Bronze/Silver/Gold Lakehouse.
RAG remains a separate document branch through S3, Bedrock Knowledge Bases,
Titan Text Embeddings V2 and S3 Vectors. Streaming is intentionally retired by
Human decision and was not replaced.

Batch and CDC each use three stage-oriented Glue jobs in a serial Step Functions
flow. This gives useful processing, retry, logging and failure boundaries at
Bronze/Silver/Gold without creating one job per table for the small workload.
Each stage receives the same `run_id` and source identity. Retries cover only
explicit transient concurrent-run/time-out categories; deterministic data or
configuration errors go through Catch, encrypted failure audit and terminal
failure.

Terraform applied exactly `8 create / 12 update / 14 destroy / 0 replace`.
Creates were four Silver/Gold Glue jobs and four stage log groups. Updates were
the Batch/CDC jobs, scripts, orchestration and scoped policies plus two AI script
objects. Destroys were the 14 Streaming-only resources. Post-apply AWS inventory
found no Streaming state machine, Glue job, EventBridge rule, IAM role, script
object or lakehouse notification; the Terraform refresh plan is zero-drift.

## Batch and data quality

- Normal run `372a8edc-4e08-0397-cefb-aee8af0c16c6`: all three stages
  `120 input / 120 output / 0 rejected / 0 duplicate`.
- Duplicate run `dd8f3e40-573b-86ab-d458-7faebd00b1a4`: a different S3 key
  with identical bytes resolved to the same SHA-256 and all stages recorded
  `DUPLICATE`, `120 input / 0 output / 120 duplicate`.
- DQ run `991f0dba-bb59-bf08-d29b-b6a02fc76983`: 120 valid rows plus one
  negative-amount row produced `121 input / 120 output / 1 rejected`, quality
  score `0.991736`, passing reconciliation and an encrypted quarantine JSON.
- Athena `435b7ad1-6b0f-4dbc-97f7-9c45824c86b7` confirmed 120 Gold rows, 120
  unique claims and zero presence of the invalid claim.
- Missing-object run `v2-batch-controlled-failure-20260911` failed once with
  `NoSuchKey`, wrote stage and orchestrator failure audits, and did not retry
  the deterministic task. After the object was supplied, recovery run
  `f2aa471c-2bea-43c4-39cd-f618f97b90d5` succeeded as a content duplicate.

The custom PySpark row checks and S3 quarantine remain in place. The amendment
adds inline AWS Glue Data Quality/DQDL to the existing Silver jobs as a second,
dataset-level gate. Batch claims use four rules: complete and unique `claim_id`,
nonnegative `claim_amount`, and complete `policy_id`. CDC current state uses the
corresponding approved rules for claims, policies, customers and payments. All
CDC candidates are evaluated before any Silver table is written. No independent
DQ schedule, recommendation, anomaly detection or ML-based DQ was added.

- FAIL: execution `c7db247d-f2c0-a256-599b-9d766c12f632...`, Silver run
  `jr_f0f43eae12af9528b84a23e0af66fce8b1549139289a63c3b6e075d596e47981`,
  Glue result `dqresult-9459d89040c80af3581e3ee410fec754a9f7e8e7` and score
  `0.75`. Three rules passed; `IsUnique "claim_id"` failed. Audit recorded four
  inputs, one quarantine rejection and zero trusted output. Athena
  `11e03078-41cd-46ce-ab28-5b6e09a052f8` proved Silver/Gold stayed at 120/120
  and summary at 30.
- PASS: execution `8aa12745-1ee9-133b-6b47-1c453921d9ec...`, Silver run
  `jr_cba863c465c4ca34168164862efcd58aefb05c6b01db4dbd3ee2dd426c8947e5`,
  Glue result `dqresult-aa2e19613ead964a3c870ccc4b194b7fc4c88e8e` and score
  `1.0`. Four of four rules passed, Gold completed, and Athena
  `70bc00a9-3273-4530-95b9-64fdfcc7e390` confirmed 120/120/120 claims plus 30
  daily-summary rows.

## CDC

Two identical full-history replays, `v2-cdc-replay-a-20260911` and
`v2-cdc-replay-b-20260911`, both completed Bronze/Silver/Gold. Each observed 14
retained changes. Silver recorded 11 current-state outputs and 2
duplicate/superseded changes with `change-log-to-current-state` reconciliation;
Gold contained three current claims.

Athena `e1660552-6a53-4f16-a681-c87e2d0666a8` confirmed three unique claims,
inserted `clm_7003`, and updated `clm_7001` to `APPROVED` with `450.00` approved
amount. The deleted source record `pay_8001` is absent; the one-row payment
baseline therefore correctly resolves to zero current payment rows.

## Control and reconciliation

Stage records are stored under
`control/v2/pipeline_runs/<run_id>/<stage>.json`; completed file identities are
stored under `control/v2/processed_files/<sha256>.json`; invalid records are
stored under `quarantine/v2/<pipeline>/<entity>/<run_id>/`. They record source,
stage, status, input/output/rejected/duplicate counts, quality/reconciliation,
error and stable identity. Batch uses the exact equation
`input = output + rejected + duplicate`; CDC explicitly reports
change-log-to-current-state semantics rather than claiming equality between
change count and current-state row count.

## ML

Athena `18dcd026-e308-4874-b4bd-da02ccbfdfe4` confirmed 120 unique feature rows,
39 positive/81 negative labels and zero invalid/future-date violations. Feature
validation rejects null/duplicate identities, invalid domains, single-class
data, post-submission as-of dates and leakage fields. The V1 target remains a
future synthetic high-severity/high-cost outcome; approved/paid amounts, final
status/severity, investigations, settlement duration and updates are excluded.

The accepted inference/identity artifacts received stable dataset version
`claim-risk-v2-af2df383c20496f5`. Existing Batch Transform output was published
twice by Glue runs
`jr_98e2f8f9080a3977ecda896ba54b6d7aa187bfc3ee0a8f631636855f44821ae6`
and `jr_8497b9ba268bf27a4ba9c196ff9ea6b915a8f3d691a2eb217b25d82f41d8c0fa`.
Athena `41dd000f-3a35-400e-acd4-63f91c493738` confirmed 120 rows, 120 unique
claims, zero missing model/dataset/run lineage and probability range
`0.36053–0.60398`. No new Training, Transform, endpoint or notebook was created.

## RAG

Two approved UTF-8 documents passed validation with stable source identity and
SHA-256 versions. Ingestion `JPIWFL7ZWT` scanned 2, failed 0, indexed/modified 0
and reconciled both as unchanged. Repeating the identical manifest recorded
`UNCHANGED_SKIPPED` and started no ingestion job. Active-ingestion overlap is
rejected; only explicit transient/429 calls receive at most three exponential
attempts. All three fixed Nova Micro questions returned non-empty answers with
S3 citations to the approved documents.

## Tests and runtime issues

- Integrated focused suite: `82 passed`.
- Terraform recursive fmt and DEV validate: passed.
- Terraform post-apply refresh plan: no changes.
- Streaming post-removal AWS and Terraform inventory: passed.
- TFLint/Checkov: unavailable and not claimed.

Routine issues corrected internally: Step Functions S3 SDK parameter casing,
pytest duplicate module names, a temporary `uv` cache collision, local missing
`boto3` resolved with an ephemeral dependency environment, and one Athena
VARCHAR/DECIMAL comparison corrected without changing data. No architecture,
security model, account plan or service scope changed.

## Cost and remaining limits

New fixed recurring V2 cost is USD 0. Glue job definitions and empty log groups
do not run compute. The validation runs consumed 3,025 Glue DPU-seconds, about
USD 0.37 at the documented USD 0.44/DPU-hour reference rate, plus negligible
small Athena, S3, Step Functions, KMS and Bedrock usage. Streaming retirement
eliminates unused scaffolding and any future Kinesis/Firehose recurring exposure.
The existing V1 RDS/DMS/PrivateLink baseline remains the dominant approved DEV
cost and was not expanded.

The Glue Data Quality amendment consumed 1,147 Glue DPU-seconds across the
diagnostic FAIL, corrected FAIL proof and final PASS workflow, approximately
USD 0.14 at the USD 0.44/DPU-hour reference rate. Athena, S3, KMS and Step
Functions test charges are negligible. It adds no fixed recurring cost; future
cost occurs only when an existing Silver job runs its inline rules.

Known V2 limits are intentional: S3 JSON rather than an enterprise metadata
store; CDC rebuilds from the small retained history; no broad schema-evolution
framework; no V3 IAM/Lake Formation PII hardening; no V4 CI/CD; no V5 complete
observability/DR; no QuickSight subscription; no Streaming replacement.

## Git

The V1 tag remains unchanged. The pre-amendment `v2.0-reliable` tag already
exists at `3fbabc3`; this amendment does not move, recreate or force-push it.
The amendment is committed and pushed to `origin/main` after final checks. V3
does not begin automatically.
