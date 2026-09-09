# V1 CDC module

Builds a private PostgreSQL source, DMS full-load-and-CDC replication to the
existing landing bucket under `oltp/`, and a Glue 5 Iceberg materialization
job. RDS logical replication is enabled with `test_decoding`; the DMS target
uses CSV with operation markers and a DMS timestamp. A Glue SQL bootstrap job
is provided because the development database is private and cannot be seeded
from a developer workstation.

Terraform generates an alphanumeric V1 database password and stores it in a
KMS-encrypted, DMS-compatible Secrets Manager secret containing the required
host and port fields. It is never represented as a Terraform variable, source
literal, tfvars value, or CLI argument; as with all Terraform-generated
credentials, its value is sensitive state and requires the approved state
handling described in the plan review. DMS and Glue receive only its ARN at
runtime and use narrowly scoped read access through a private interface endpoint.
Run the seed job first, confirm the schema, then start the DMS task. The S3
EventBridge rule starts the CDC Glue state machine for each DMS object. V1
refreshes current-state Iceberg tables from the available DMS files; robust
completion ledgers, replay, deduplication, quarantine, and reconciliation are
V2 concerns.
