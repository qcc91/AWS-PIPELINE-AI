# V2 infrastructure and orchestration review

Date: 2026-09-11

Region: `ap-southeast-2`
Status: applied and verified in DEV

## Scope

This package retires the Kinesis/Firehose-only V1 path and gives the retained
Batch and CDC ingestion patterns separate Bronze, Silver, and Gold operational
boundaries. It reuses the existing landing, lakehouse, control, quarantine,
KMS, Glue Catalog, EventBridge, and Step Functions resources. It introduces no
replacement streaming technology and no continuously running resource.

## Streaming retirement evidence

Terraform state and AWS were both inspected before removal. The inventory below
describes the pre-apply state and the verified result.

- Pre-apply Terraform state contained 14 `module.streaming` resources: one Glue job, one
  Step Functions state machine, one EventBridge rule and target, one CloudWatch
  log group, four IAM roles, three inline policies, one S3 EventBridge bucket
  notification, and one encrypted Glue script object.
- The Glue job `insurance-dev-stream-iceberg`, state machine
  `insurance-dev-streaming`, EventBridge rule
  `insurance-dev-stream-object-created`, its target, the four roles, and the
  script object were confirmed in the real account.
- No Kinesis stream, Firehose delivery stream, producer policy, or Firehose
  inline policy is in Terraform state. The account still rejects Kinesis and
  Firehose list operations with the known subscription restriction, so state
  plus the prior failed-create evidence is the authoritative absence check.
- The lakehouse bucket currently has only the Streaming-owned EventBridge
  notification. The Batch notification is independently managed on the
  landing bucket. Retiring the lakehouse notification therefore does not alter
  Batch or CDC event delivery.

The active DEV root no longer references the Streaming module or exports
Streaming outputs. The obsolete module files are removed. The approved apply
removed all 14 resources. Post-apply AWS checks found no matching state machine,
Glue job, EventBridge rule, IAM role, script object, or lakehouse notification;
Terraform state contains no Streaming address.

## Medallion job boundaries

Batch and CDC each use three Glue job resources executed serially:

`EventBridge -> Step Functions -> Bronze -> Silver -> Gold`

The existing V1 Glue job names and resource addresses are retained for the
Bronze jobs to avoid an unnecessary replacement. New `-silver` and `-gold`
jobs establish the additional boundaries. Each stage receives the same
`run_id` and source identity plus `--PROCESSING_STAGE`. Each new stage has its
own 30-day CloudWatch log group. This is stage-oriented rather than
table-oriented: it provides useful failure and retry isolation without
creating a job per table.

Each Glue task has exponential backoff with two retries after the initial
attempt (three total attempts), followed by a catch-all transition to an
explicit failed state. Retry is deliberately limited to concurrent-run and
timeout errors; the broad `States.TaskFailed` category is not retried because
it can include deterministic schema or configuration failures. Before entering
the failed state, the orchestrator writes the captured stage error to
`control/v2/pipeline_runs/<run_id>/<stage>-failure.json` using the Step
Functions S3 SDK integration. Deterministic invalid rows are handled by the data
quality/quarantine contract inside the stage and are not expected to fail the
orchestrator. Step Functions execution history and the stage audit record form
the infrastructure failure audit boundary.

The confirmed runtime contract includes:

- Batch: `JOB_NAME`, `PROCESSING_STAGE`, `RUN_ID`, `LANDING_BUCKET`,
  `LANDING_KEY`, `LAKEHOUSE_BUCKET`, Bronze/Silver/Gold database names,
  `CONTROL_BUCKET`, `QUARANTINE_BUCKET`, and optional V2 prefixes.
- CDC: the same stage/control/quarantine contract using `CDC_PREFIX` and
  `CDC_OBJECT_KEY` for its source identity.

## IAM, encryption, and retained resources

No new IAM role or KMS key was created. The existing Batch and CDC Glue role
policies gain:

- bucket-list access to the existing quarantine bucket;
- `GetObject`, `GetObjectVersion`, and `PutObject` only under
  `quarantine/v2/*`;
- access to the existing control bucket already used for scripts and control
  metadata.

The existing Step Functions roles gain `s3:PutObject` only for
`control/v2/pipeline_runs/*` plus the three KMS operations required to encrypt
those failure records. They do not gain bucket-wide read or delete access.

Quarantine access deliberately excludes `DeleteObject`. Both buckets already
use the platform KMS key, and the existing Glue roles already have the required
cryptographic operations. Shared Batch, CDC, BI, ML, RAG, S3, KMS, and Glue
Catalog resources are not selected for destruction.

## DEV plan summary

The saved DEV plan and its exact apply reported:

- create: 8
- change in place: 12
- destroy: 14

The eight creates are four short-lived-on-use Glue job definitions and four
30-day log groups. The 14 destroys are exactly the state-backed Streaming-only
resources described above. In-place changes include the Batch/CDC Glue jobs,
their policies, orchestration, and script artifacts plus two AI runtime script
objects.
There are no replacements and no retained data bucket, database, DMS, RDS,
ML, BI, or RAG destroys.

Apply completed as `8 added, 12 changed, 14 destroyed`; a subsequent refresh
plan returned `No changes`. No replacement occurred.

## Cost impact

Incremental fixed monthly cost is expected to be USD 0. Empty Glue job
definitions and log groups do not run compute. Runtime cost increases because
one combined invocation becomes three independently billed Glue invocations.
Using two G.1X workers and the one-minute minimum, the planning floor is about
USD 0.044 for a complete three-stage path at the AWS example rate of USD 0.44
per DPU-hour, versus about USD 0.015 for one stage. Actual Sydney charges depend
on runtime and regional pricing. Step Functions transitions, S3 audit records,
and low-volume logs are negligible at demo scale. Removing Streaming-only
resources eliminates its unused orchestration/log storage and prevents any
future Kinesis/Firehose recurring cost.

Pricing reference: https://aws.amazon.com/glue/pricing/

## Validation

- `terraform fmt -recursive terraform`: passed
- `terraform validate` for DEV: passed
- integrated focused V2 tests: 79 passed
- existing PowerShell infrastructure validation: passed
- `git diff --check` for Terraform/infrastructure tests: passed
- `tflint`: not installed
- `checkov`: not installed

The AWS changes are exactly the applied counts above. No shared data bucket,
database, RDS, DMS, BI, ML, RAG, KMS, or Glue Catalog resource was destroyed.
