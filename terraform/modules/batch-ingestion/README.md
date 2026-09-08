# Batch ingestion module

Creates the V1 broker claim CSV ingestion boundary on top of existing S3
landing/lakehouse/control buckets and Glue Catalog databases. The module owns
the S3 EventBridge notification, EventBridge rule/target, Step Functions state
machine, Glue job, execution roles/policies, job artifact object, and log
groups. It does not create buckets, KMS keys, databases, networks, or
long-running compute.

The supplied Glue script must be a local path to `jobs/glue_claim_pipeline.py`
or a compatible Glue 5 Spark/Iceberg script. The landing event filter only
accepts objects below `batch/` by default.
