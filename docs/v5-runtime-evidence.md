# V5 DEV runtime evidence

## Deployment

On 2026-09-15 the separately managed bootstrap layer applied one existing
TerraformExecution inline-policy update: 0 add, 1 change, 0 destroy. Existing
statements were compared with the binary plan and preserved. Only bootstrap
used the pre-existing bootstrap administrator session.

Human MFA -> Operator -> TerraformExecution was verified for all DEV applies.
The monitoring apply created eight resources and updated the audit KMS policy
in place, without deletion or replacement. Four CloudWatch alarms, the Glue
EventBridge rule/target, DMS event subscription and SNS topic policy exist.
DMS subscription `insurance-dev-dms-task-failures` is `active` and limited to
existing task `insurancedevcdc`.

A subsequent in-place DataEngineer policy update permits operational alarm
history and Sydney metrics reads. Two workflow alarms were subsequently changed
to five-minute metric periods. No additional compute or KMS key was created.

During the CDC recovery proof, the separately managed bootstrap layer added
only `s3:PutObject` and `s3:PutObjectTagging` for project
`artifacts/glue/*`. This does not grant bucket-wide data writes, deletes,
Human-IAM administration or bootstrap state/KMS administration. The CDC script
was then updated through TerraformExecution with `0 add / 1 change / 0 destroy`.

## Missing-input failure and notification

- Execution: `arn:aws:states:ap-southeast-2:199476069493:execution:insurance-dev-batch-claim-lakehouse:v5-missing-20260915T050222Z-b6bc8e66`.
- Started: `2026-09-15T05:02:23.949Z`; failed: `05:03:21.445Z`.
- Terminal error: `BatchMedallionStageFailed`.
- Audit object exists at `control/v2/pipeline_runs/v5-missing-20260915T050222Z-b6bc8e66/bronze.json` in the existing control bucket.
- AWS/States ExecutionsFailed: Sum 1 in the `05:03Z` minute.
- Batch alarm entered ALARM at `05:04:50.324Z`.
- Alarm action history at `05:04:50.382Z` reports successful execution of the
  existing `insurance-dev-critical-alerts` SNS action.
- Alarm returned to OK at `05:05:50.324Z`.
- Glue failure EventBridge rule: Invocations Sum 1 in the `05:04Z` minute;
  no FailedInvocations datapoint returned for the observation window.
- SNS NumberOfMessagesPublished: Sum 2 in the `05:04Z` minute.

This proves publication to SNS, not delivery to a human inbox: no human endpoint
has been subscribed. The initial one-minute alarm did fire after metric delivery
delay; it did not permanently miss the failure. The later five-minute period
also detected the controlled CDC failure: the alarm entered `ALARM` at
`2026-09-15T21:44:38.769Z`, successfully invoked the SNS topic, and returned to
`OK` at `21:49:38.762Z`. SNS recorded two published messages in the relevant
five-minute interval.

## Continued validation

- Git checkpoint `a7836ae4714cc8867f395cad3bac2f105e1b8031` is pushed to
  `codex/v5-production-readiness`; draft PR #5 targets protected `main`.
- Full PR CI run `34960670050` succeeded on this checkpoint.
- Full DEV non-root Terraform post-apply plan returned `No changes`.
- Batch key baseline query `465c1250-5a26-4d6d-912d-234d1bed1df5` returned
  120 rows/keys, matching the 120 repository keys exactly.
- Source provenance query `465ee11e-ade7-4464-8917-01292afdbab0` identified
  `batch/broker_claims_dq_pass.csv` as the current 120-row Silver source.
  The drill uses that downloaded source snapshot, not an assumed older file.
- CDC baseline query `58d78b3e-ff81-4b29-aae8-8e8c4b704340`: 3 rows, 3 unique claims.
- Bad-data upload under `batch/v5-drill/v5-batch-ops-20260915T110016Z-3e9c27cc/`
  automatically triggered execution
  `bfa4909e-ae43-ccd4-6f09-68fbd3c7dde3_cff95c43-911a-76b5-7cfb-0196a9a38a3e`.
  Its audit run ID is `bfa4909e-ae43-ccd4-6f09-68fbd3c7dde3`.
- Bad-data Silver audit: `input_count=121`, `output_count=120`,
  `rejected_count=1`, `duplicate_count=0`, `reconciliation_passed=true`.
  All four Glue DQ candidate rules passed after quarantine, score 1.0.
  Row acceptance quality was 120/121 = 0.991736. A quarantine object exists
  under `quarantine/v2/batch/claim/bfa4909e-ae43-ccd4-6f09-68fbd3c7dde3/`.

## Recovery, replay and reconciliation

- Corrected Batch execution
  `e256fc11-b3af-e7f2-19b2-930db77c3e24_757cdfdb-7f46-62eb-0572-44417d776762`
  succeeded. Bronze/Silver/Gold each reconciled `121 input = 121 output + 0
  rejected + 0 duplicate`; Silver Glue DQ passed 4/4 rules.
- Byte-identical replay execution
  `cc9611f8-c6d6-e1fb-15ee-6d4ec2cd2f62_9847717a-71ae-8018-d902-193ab89f2498`
  succeeded as a no-op. Every stage reported `DUPLICATE`, with `121 input`,
  `0 output` and `121 duplicate`.
- Final Batch Athena query `f211ce14-e4c8-4b2a-930e-86c306d5ca85`
  returned 121 rows, 121 unique claim IDs, zero negative amounts and exactly one
  corrected drill claim. It scanned 678 bytes.
- The first CDC replay exposed a real Silver boundary defect: DMS CSV amounts
  were still strings when Glue DQ evaluated numeric rules. The job now applies
  the documented decimal/date/timestamp Silver contract before DQ. Focused
  tests passed and the actual S3 script SHA-256 matched the repository.
- Corrected CDC execution
  `v5-cdc-replay-20260916T012503Z-aea31e27` succeeded. Bronze processed 14
  changes; Silver produced 11 current-state records with two historical
  duplicates; all 10 applicable DQ rules passed; Gold published three claims.
- Athena queries `2f92530e-9f3a-49b6-94f8-88295e0bb08f`,
  `95de5099-7c6a-4505-b24c-3b661ab33574` and
  `74b0ef33-8b7d-4339-a21b-b834179bc7e4` confirmed three unique claims,
  `clm_7001=APPROVED/450.00`, `clm_7003=SUBMITTED`, and zero rows for deleted
  payment `pay_8001`.

## Security, tests, drift and cost

- Human and Operator direct data access: DENY.
- Analyst approved Gold: ALLOW; Silver and Secrets: DENY.
- MLEngineer approved feature table: ALLOW; general Silver and Secrets: DENY.
- RAGApplication Knowledge Base retrieval: ALLOW; direct Lakehouse: DENY.
- CloudTrail logging and log-file validation remain enabled.
- Local integrated suite: 115 passed. Terraform fmt/validate, repository
  consistency, high-confidence credential scan and `git diff --check` passed.
- Final Terraform plans: bootstrap `No changes`; DEV foundation `No changes`
  using the non-root TerraformExecution path.
- The controlled Glue runs consumed 2,429 DPU-seconds, approximately USD 0.30
  at USD 0.44 per DPU-hour, before any free allowance. Athena scanned less than
  one kilobyte in the four final reconciliation queries. The conservative new
  recurring alarm estimate remains at or below about USD 0.60/month before
  free allowance; EventBridge, SNS and DMS subscription have no material fixed
  charge at this volume. This remains below the USD 12/month review threshold.

## Operational limitations

For subsequent full DEV plans, explicitly supply the existing
`TF_VAR_v3_operator_role_arn` and `TF_VAR_v3_terraform_execution_role_arn` with
the bootstrap-managed Operator and TerraformExecution ARNs. Their current
optional defaults are null; omitting them attempts to disable V3 resources and
is rejected by `prevent_destroy`. Never bypass that protection.

The local provider could not read the nested CLI login profile directly.
`aws configure export-credentials --profile aip-dev-terraform --format process`
was captured into a process variable and supplied through process-only AWS
environment variables. No credential value was printed or persisted.

- The SNS topic has no human email/SMS subscriber; AWS publication is proven,
  but human inbox delivery is intentionally not claimed.
- The pre-existing DMS task status remains `failed`. V5 proves recovery from
  retained DMS history without restarting or mutating DMS/RDS.
- QuickSight remains unsubscribed and the full PROD platform remains out of
  scope. No new SageMaker or Bedrock workload was run for V5.
- V5 implementation is complete but is not accepted or tagged until the Human
  approves the consolidated checkpoint.
