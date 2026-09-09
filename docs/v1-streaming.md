# V1 streaming happy path

## Current runtime status

Implementation and offline validation are complete, but the DEV account returns
`SubscriptionRequiredException` for the Kinesis API in `ap-southeast-2`.
Terraform therefore has not created the four remaining Streaming resources
(Kinesis stream, Firehose delivery stream, Firehose policy, and producer
policy). Do not retry apply until a read-only Kinesis capability preflight
succeeds.

Live account discovery on 2026-09-10 confirmed `accountPlanType=FREE`. Both
Kinesis `ListStreams` and Firehose `ListDeliveryStreams` return: `The AWS Access
Key Id needs a subscription for the service`. AWS lists Kinesis Data Streams
and Amazon Data Firehose as Paid Plan services for this account type. The Human
Owner must upgrade the AWS account to `PAID`; this billing-plan change is not an
autonomous engineering action.

## Flow

`src/streaming/producer.py` creates schema-version-1 JSON envelopes and sends
them to the one-shard DEV Kinesis stream. A Kinesis-source Firehose buffers
newline-delimited JSON and delivers compressed objects under
`s3://<lakehouse>/stream/`. `jobs/glue_streaming_pipeline.py` reads that prefix
and writes `bronze.stream_event`, `silver.stream_event`, and
`gold.event_daily_summary` as Iceberg tables in the existing Glue Catalog.

Every event contains `schema_version`, `event_id`, `event_type`,
`event_timestamp` (UTC), `source`, `payload`, and at least the business IDs
required by its event type. Payloads must not contain credentials, card data,
or unnecessary PII.

## Offline checks

```powershell
python -m pytest tests/streaming -q
python -m py_compile src/streaming/producer.py jobs/glue_streaming_pipeline.py
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev validate
```

Terraform validation may require the already-approved provider cache and
backend configuration. These checks are read-only.

## Athena verification after approved DEV deployment

```sql
SELECT event_type, source, event_date, event_count
FROM insurance_dev_gold.event_daily_summary
ORDER BY event_date, event_type;
```

Validate that event counts match the Firehose-delivered sample, that
`silver.stream_event` timestamps are UTC and non-null, and that Bronze retains
the original envelope plus `_run_id`, `_source_system`, `_ingested_at`, and
`_record_hash` metadata. After Firehose creates a `stream/` object, the S3
EventBridge notification starts a Standard Step Functions execution. The
state machine invokes Glue with `.sync`, passing the EventBridge event ID as
`RUN_ID`; its prefix rule does not match Iceberg output under `lakehouse/`.

## Cost and limitations

The path uses one provisioned Kinesis shard (24-hour retention), on-demand
Firehose, and a short two-worker Glue job. There is no NAT Gateway or
always-running compute beyond the continuously billed provisioned Kinesis
shard. Kinesis/Firehose/Glue/S3 usage is otherwise pay-per-use, subject to the
project's approved AWS account and region; include the ongoing shard cost in
the Gate 2 review. V2 adds bounded retries,
deduplication, quarantine, and reconciliation; V1 is intentionally a happy
path and does not claim those guarantees.
