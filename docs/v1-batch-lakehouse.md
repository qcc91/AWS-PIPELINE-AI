# V1 batch claim lakehouse

The V1 batch happy path accepts a synthetic broker claim CSV under
`s3://<landing>/batch/`. Amazon S3 publishes an Object Created event to the
default EventBridge bus. The rule starts the Step Functions execution, which
passes the bucket, object key, and EventBridge event ID (`run_id`) to a
short-running AWS Glue 5.0 Spark job.

The job writes all three layers as Apache Iceberg tables in the existing
`<lakehouse>/lakehouse/` prefix:

| Layer | Glue table | Stable location | V1 behavior |
|---|---|---|---|
| Bronze | `insurance_dev_bronze.claim` | `lakehouse/bronze/claim/` | Source columns as strings plus source/run metadata |
| Silver | `insurance_dev_silver.claim` | `lakehouse/silver/claim/` | Typed dates/timestamps/decimal amounts, uppercase statuses, latest `claim_id` |
| Gold | `insurance_dev_gold.fact_claim` | `lakehouse/gold/fact_claim/` | Claim fact with description removed |
| Gold | `insurance_dev_gold.claim_daily_summary` | `lakehouse/gold/claim_daily_summary/` | Count and amount totals by incident date/status/currency |

The module reuses the deployed landing, lakehouse, control, KMS, and Glue
Catalog foundation resources. It creates one Glue job, three execution roles,
two log groups, one Step Functions state machine, one EventBridge rule/target,
one S3 EventBridge notification configuration, and one versioned Glue script
object. IAM access is scoped to the three existing buckets, platform KMS key,
three Catalog databases/tables, the job log group, and the state machine. The
existing V1 platform KMS policy deliberately keeps `user_role_arns=[]`; the
temporary root/account statement delegates its enumerated data actions, while
V3 will add explicit least-privilege role principals after role lifecycle is
managed safely. New application log groups use the CloudWatch Logs service's default encryption;
the existing audit log group remains KMS-encrypted by the foundation.
The optimized Step Functions Glue integration requires the Glue polling/start
permissions on `Resource="*"` (including `GetJobRuns`); this is an AWS service
integration limitation and is intentionally documented for the V1 scope.

## Deployed and verified

The Human-approved 14/0/0 plan was applied in DEV on 2026-09-09. The synthetic
file was uploaded to
`s3://aip-insurance-dev-landing-dev01/batch/broker_claims-v1.csv`. EventBridge
started Step Functions, the Glue job completed in 82 seconds, and the four
Iceberg tables were registered in the Glue Catalog. Athena returned 3 Bronze
rows, 3 Silver rows, 3 `fact_claim` rows, total claim amount 5290.50, total
approved amount 800.00, and one expected row for each APPROVED, SUBMITTED, and
UNDER_REVIEW daily summary group.

## V1 boundary and cost assumptions

This is a functional demonstration path. A rerun currently refreshes the
tables and does not implement the V2 completion ledger, quarantine paths,
bounded retries, reconciliation, or full replay/idempotency semantics. Invalid
rows are filtered by the Glue job and surfaced through job failure/logs rather
than being retained in a V1 quarantine dataset; those controls are V2 work.

Glue uses two on-demand G.1X workers and a 15-minute timeout. At the commonly
published $0.44/DPU-hour Glue ETL rate, the upper bound is about $0.22 per
15-minute run before storage/request charges; actual short runs are lower.
There is no
always-on compute, NAT Gateway, endpoint, subscription, or alarm in this
module. The expected incremental spend is normally a few cents per demo run
(Glue DPU-seconds, S3 requests/storage, CloudWatch logs, EventBridge,
Step Functions); exact pricing depends on run duration and AWS regional rates.

## Reviewed Terraform plan and apply

The real DEV plan generated on 2026-09-09 contains 14 creates, zero changes,
and zero destroys. Every action is under `module.batch_ingestion`; the deployed
bootstrap and foundation resources have no planned mutation. The plan creates
three IAM roles and policies, two log groups, one Glue job, one Standard state
machine, one EventBridge rule/target, one landing-bucket EventBridge
notification configuration, and one versioned Glue script object.

The approved plan was applied without resource-count deviation: 14 created,
zero changed, and zero destroyed. A post-apply refresh plan reports no changes.
The combined foundation/batch state contains 76 resources; the separate
bootstrap state contains 9. Saved binary plans and Terraform state remain
Git-ignored.
