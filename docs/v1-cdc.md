# V1 PostgreSQL CDC happy path

This package adds a small private PostgreSQL DEV source and replicates the
five contract tables (`customers`, `products`, `policies`, `claims`, and
`payments`) with AWS DMS `full-load-and-cdc` into the existing landing bucket
under `oltp/`. DMS uses PostgreSQL logical replication with the
`test_decoding` plugin and writes encrypted CSV change files including an
operation marker and `_dms_timestamp`.

The module expects the already-deployed VPC, private subnets, landing and
lakehouse buckets, platform KMS key, and Glue Catalog databases. The initial
Worker estimate was 35 resource instances. The reviewed design also adds
a Secrets Manager interface endpoint/security group, a DMS-compatible secret
and version, and a generated password resource. The final count is determined
from the real Terraform plan rather than this design estimate. Core resources
include RDS subnet/parameter/instance,
two DMS IAM roles and policies, DMS subnet/replication instance/endpoints/task,
five controlled S3 artifacts, two log groups, Glue role/policy/connection and
two jobs, a Step Functions role/policy/state machine, and an EventBridge
role/policy/rule/target. No NAT Gateway, public subnet, EC2, or new data store
is introduced.

## Private initialization and demo order

AWS DMS cannot use an RDS-managed master secret because it omits the host and
port fields DMS requires. Terraform therefore generates an alphanumeric V1
password and places the complete connection document in a customer-KMS-encrypted
Secrets Manager secret. The value is sensitive Terraform state but never enters
source, tfvars, command output, or Git. The Glue SQL job runs in the private subnet using the RDS
security group path, so a developer workstation does not need private network
access. DMS and Glue reach the secret through a private Secrets Manager interface
endpoint in both CDC subnets:

1. Apply only after a separate Human-approved CDC plan gate.
2. Run the `cdc_seed_job_name` Glue job with `--ACTION schema_seed`.
3. Start the DMS task and wait for full load to reach `load complete`.
4. Run the CDC Glue job once to materialize Bronze/Silver/Gold.
5. Run the seed job with `--ACTION mutations` to produce an INSERT, UPDATE,
   and DELETE; wait for DMS files and run the CDC job again.

The S3 EventBridge rule can start the CDC state machine for `oltp/` objects.
The state machine passes the changed key and run ID to Glue; the job reads the
available table directory and refreshes current-state Iceberg tables. DMS may
emit several files in a burst, so V1 deliberately keeps the job single-run
and may require one final manual CDC run after the burst.

## Outputs and validation

Silver tables are `insurance_dev_silver.{customers,products,policies,claims,payments}`.
CDC Bronze tables are `insurance_dev_bronze.{customers_cdc,...}`. Gold CDC
outputs are `insurance_dev_gold.fact_claim_cdc` and
`insurance_dev_gold.claim_daily_summary_cdc`. The expected synthetic proof is
that `clm_7003` exists after INSERT, `clm_7001` has status `APPROVED` and
approved amount `450.00` after UPDATE, and `pay_8001` is absent after DELETE.

## Cost, security, and V1 limits

The always-on cost drivers are one `db.t4g.micro` RDS instance, one
`dms.t3.small` replication instance, and the two-AZ Secrets Manager interface
endpoint. AWS Price List discovery in Sydney found RDS compute at USD 0.025/hour
(about USD 18.25/730 hours) and single-AZ DMS compute at USD 0.056/hour (about
USD 40.88/730 hours), before storage, endpoint, Secrets Manager, and request
charges. This exceeds the USD 12/month review threshold and requires a Human
cost decision before apply. Glue is on-demand, two G.1X workers, and 15 minutes per
run (roughly USD 0.22 at USD 0.44/DPU-hour). Stop or destroy the DEV package
only through an approved Terraform change; the module protects the RDS from
accidental destroy.

The generated database password is stored only as sensitive Terraform state
and in Secrets Manager, never in Git or plan output. The current V1 local-state
shortcut therefore requires restricted workstation access and is not the V3/V4
target state design.

V1 does not implement a completion ledger, bounded retries, quarantine,
reconciliation, DMS failover, CDC replay, or schema evolution. These are V2–V5
work. PostgreSQL parameter changes use `pending-reboot`; a newly-created RDS
instance normally applies them during creation, while an existing instance
requires an approved reboot before CDC can start.
