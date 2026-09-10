# Batch ingestion module

Creates the shared V1 batch CSV ingestion boundary on top of existing S3
landing/lakehouse/control buckets and Glue Catalog databases. The same boundary
handles the original broker claim CSV and the file-based master/reference
datasets. The module owns the S3 EventBridge notification, EventBridge
rule/target, Step Functions state machine, Glue job, execution roles/policies,
job artifact object, and log groups. It does not create buckets, KMS keys,
databases, networks, or long-running compute.

The supplied Glue script must be a local path to `jobs/glue_claim_pipeline.py`
or a compatible Glue 5 Spark/Iceberg script. The landing event filter accepts
objects below `batch/` by default, so both `batch/broker_claims-v1.csv` and
objects below `batch/reference/` use this path without additional AWS
resources. The Glue script is responsible for routing supported filenames to
the appropriate Bronze, Silver, and Gold Iceberg tables.

The EventBridge rule passes the bucket, decoded object key, and event ID through
Step Functions to the single Glue job. Its IAM policy already allows reads from
the complete `batch/` prefix and writes to all three existing lakehouse layers.
This expansion therefore needs no new role, bucket, rule, state machine, job,
or continuously running service.
