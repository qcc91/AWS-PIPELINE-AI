# V5 DEV runtime evidence (in progress)

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
delay; it did not permanently miss the failure. Its later five-minute period
is intended to tolerate reporting delay and still needs final verification.

## Remaining

For subsequent full DEV plans, explicitly supply the existing
`TF_VAR_v3_operator_role_arn` and `TF_VAR_v3_terraform_execution_role_arn` with
the bootstrap-managed Operator and TerraformExecution ARNs. Their current
optional defaults are null; omitting them attempts to disable V3 resources and
is rejected by `prevent_destroy`. Never bypass that protection.

The local provider could not read the nested CLI login profile directly.
`aws configure export-credentials --profile aip-dev-terraform --format process`
was captured into a process variable and supplied through process-only AWS
environment variables. No credential value was printed or persisted.

Baseline-preserving bad-data isolation, successful recovery, duplicate replay,
CDC replay, final reconciliation/security checks, final drift, and protected
PR/CI remain pending. V5 is not complete or accepted.

Local integrated tests after initial deployment: 114 passed.
