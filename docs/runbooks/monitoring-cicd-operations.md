# Monitoring and CI/CD Operations Runbook

## Safety and identity

These procedures cover the existing Sydney DEV monitoring path and the V4B
minimal deployment proof. Authenticate through Human MFA and the appropriate
Operator/read-only role. Do not use root, create access keys, bypass GitHub
checks, manually start CodePipeline, approve PROD, or rerun an apply merely to
test observability.

The operational topic is `insurance-dev-critical-alerts`. It intentionally has
no Terraform-created human subscription. Alarm wiring is therefore validated
through alarm history, topic/rule configuration and CloudTrail evidence until
a Human Owner explicitly supplies and confirms an endpoint.

## Alarm investigation

**Symptom:** an alarm is `ALARM`, or a Glue/DMS failure event reaches the SNS
topic.

1. Capture alarm name, transition timestamp and reason:

   ```powershell
   aws cloudwatch describe-alarms --region ap-southeast-2 --alarm-name-prefix insurance-dev-
   aws cloudwatch describe-alarm-history --region ap-southeast-2 --alarm-name <alarm-name> --history-item-type StateUpdate --max-records 20
   ```

2. Verify that the alarm still points only to the approved topic:

   ```powershell
   aws sns get-topic-attributes --region ap-southeast-2 --topic-arn arn:aws:sns:ap-southeast-2:199476069493:insurance-dev-critical-alerts
   ```

3. For Batch/CDC workflow alarms, identify the terminal execution and continue
   with `data-pipeline-operations.md`. For a Glue event, capture `jobName`,
   `jobRunId`, state and sanitized failure reason, then use its Glue section.
   Never include PII or source rows in an incident note.
4. Confirm the alarm returns to `OK` only after a successful corrected run and
   the evaluation window expires. Do not use `SetAlarmState` as recovery.

Escalate when the target topic/rule is missing, an alarm has an unexpected
action, the same deterministic error recurs after correction, or recovery
would require deleting/replacing an accepted resource.

## Glue and DMS route validation

Use read-only inspection to confirm the exact route:

```powershell
aws events describe-rule --region ap-southeast-2 --name insurance-dev-glue-job-failures
aws events list-targets-by-rule --region ap-southeast-2 --rule insurance-dev-glue-job-failures
aws dms describe-event-subscriptions --region ap-southeast-2 --filters Name=event-subscription-id,Values=insurance-dev-dms-task-failures
```

The Glue rule must match only the listed existing jobs and terminal states
`FAILED`, `STOPPED`, and `TIMEOUT`. The DMS subscription must contain only the
existing `insurancedevcdc` replication task and the `failure` category. The
pre-existing failed DMS status is a known limitation; monitoring does not repair
or restart the task.

## GitHub CI failure

**Symptom:** the protected PR check `Terraform, Python, and security checks`
fails.

1. Open the failed GitHub Actions job and identify the first failing step.
2. Reproduce only that gate locally: Terraform formatting/validation, focused
   pytest, repository consistency or credential scanning.
3. Correct the branch and push normally. Keep branch protection and required
   checks enabled; do not force-push or merge a failing PR.
4. After all required checks pass, merge only with Human/Manager authorization.

A PR failure never justifies an AWS apply or a manual pipeline execution.

## CodePipeline or CodeBuild failure

**Symptom:** `insurance-dev-v4b-cd` or a deployment build fails.

```powershell
aws codepipeline get-pipeline-state --region ap-southeast-2 --name insurance-dev-v4b-cd
aws codepipeline list-pipeline-executions --region ap-southeast-2 --pipeline-name insurance-dev-v4b-cd --max-results 10
aws codepipeline get-pipeline-execution --region ap-southeast-2 --pipeline-name insurance-dev-v4b-cd --pipeline-execution-id <execution-id>
aws codebuild batch-get-builds --region ap-southeast-2 --ids <build-id>
```

Capture execution ID, source SHA, failed stage/action, build ID and sanitized
phase context. Inspect the existing 30-day log group for the exact project:

- `/aws/codebuild/insurance-dev-v4b-deploy-dev`
- `/aws/codebuild/insurance-dev-v4b-plan-prod`
- `/aws/codebuild/insurance-dev-v4b-apply-prod`

Correct source/configuration through a protected PR. A normal merge to `main`
starts the next execution. Do not manually call `StartPipelineExecution`, reuse
an old binary plan, or widen a CodeBuild/proof role to avoid diagnosis.

## PROD approval/deployment troubleshooting

The V4B PROD proof is the only PROD resource in this runbook; this is not a
full-platform deployment procedure.

Before approval, compare the source SHA, pipeline execution ID, exact plan
SHA-256, and reported create/change/destroy/replace counts with the approval
summary. The `PRODApproval / ApproveExactPlan` action must remain in progress
until the Human Owner explicitly approves that exact binary plan.

If approval expires, metadata differs, the plan artifact is missing, or any
destroy/replace appears, reject/leave the action unapproved and create a new
normal PR correction. Never regenerate a plan inside the apply stage and never
approve a different execution by analogy.

After an authorized apply, verify the pipeline succeeded and the proof root
reports `No changes`. Escalate immediately if the full DEV foundation changed,
the dedicated `proof-prod-apply` role was not the execution identity, or the
applied plan checksum differs from the approved checksum.
