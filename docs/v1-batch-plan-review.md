# V1 batch lakehouse Terraform plan review

Date: 2026-09-09

Status: ready for Human Terraform plan approval. No batch resources have been
applied.

## Exact actions

| Resource type | Create | Change | Destroy |
|---|---:|---:|---:|
| IAM role | 3 | 0 | 0 |
| IAM inline role policy | 3 | 0 | 0 |
| CloudWatch log group | 2 | 0 | 0 |
| Glue job | 1 | 0 | 0 |
| Step Functions state machine | 1 | 0 | 0 |
| EventBridge rule | 1 | 0 | 0 |
| EventBridge target | 1 | 0 | 0 |
| S3 EventBridge notification configuration | 1 | 0 | 0 |
| Versioned S3 Glue script object | 1 | 0 | 0 |
| **Total** | **14** | **0** | **0** |

All actions are confined to `module.batch_ingestion`. The plan does not mutate
the existing 9 bootstrap or 62 foundation resource instances.

## Functional path

Synthetic broker claim CSV objects under `landing/batch/` emit S3 events to
EventBridge. A Standard Step Functions workflow passes the bucket, decoded
object key, and event ID as run ID to a synchronous Glue 5.0 job. The job
creates/replaces `bronze.claim`, `silver.claim`, `gold.fact_claim`, and
`gold.claim_daily_summary` as Iceberg v2 tables in the existing lakehouse
bucket and Glue databases.

## Security and cost review

The package creates no public resource, long-running compute, NAT Gateway, or
new KMS key. It reuses the existing SSE-KMS buckets and platform key. Glue data,
catalog, and log access is scoped to the V1 resources. EventBridge can start
only the batch state machine. AWS's optimized Glue `.sync` integration requires
`StartJobRun`, `GetJobRun`, `GetJobRuns`, and `BatchStopJobRun` with
`Resource="*"`; no other Glue actions receive that wildcard.

Idle cost is limited to very small log/script storage. Glue uses two G.1X
workers, is billed only while running, and has a 15-minute timeout. Using AWS's
published USD 0.44/DPU-hour example, a full-timeout run is approximately USD
0.22 before negligible request/log/storage charges. The expected V1 demo uses
one to five runs (up to about USD 1.10 incremental). Repeated full-timeout runs
must be stopped before they materially exceed the USD 12 monthly review
threshold.

## Evidence and limitations

Terraform format/validation, Python compilation, 10 unit/static tests, and Git
whitespace checks pass. Bronze, Silver, and Gold Iceberg configuration and the
EventBridge-to-Step-Functions-to-Glue parameter contract are statically tested.

V1 intentionally omits the V2 completion ledger, robust replay/idempotency,
bounded retries, quarantine retention, reconciliation, and full audit metrics.
The post-apply smoke test will upload only the repository's synthetic CSV,
wait for the workflow, verify four Iceberg tables in Glue, and query counts and
totals before declaring the package functional.
