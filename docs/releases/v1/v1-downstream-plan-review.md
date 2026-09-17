# V1 Downstream Terraform Plan Review

## Plan identity

- Generated: 2026-09-09
- Environment: DEV
- Region: `ap-southeast-2`
- Account: `199476069493`
- Execution: Human-approved temporary V1 root session
- Plan artifact: local `.terraform/v1-unified.tfplan` (Git ignored)
- Apply performed: No

Terraform refreshed the existing DEV state before planning. The trustworthy
unified plan is:

- Create: 78
- Change in place: 1
- Destroy: 0
- Existing no-op resources: 75

The 78 creates are split by module: CDC 39, Streaming 18, ML 10, RAG 8, and BI
3. QuickSight remains disabled because the account is not subscribed.

## Planned resources

The plan creates one private PostgreSQL RDS instance, one DMS replication
instance and its endpoints/task, one two-AZ Secrets Manager interface endpoint,
one secret, Glue jobs/connections, EventBridge/Step Functions orchestration,
one provisioned Kinesis shard, Firehose, Athena workgroup/named queries,
SageMaker role/artifacts/model package group, and one Bedrock Knowledge Base
with an S3 Vectors index and two approved synthetic documents.

The only in-place change is the existing platform KMS key policy. It adds
`kms:CreateGrant` for the same-account root principal only when
`kms:GrantIsForAWSResource=true`; the existing enumerated V1 root actions remain
unchanged. This is needed by AWS-managed workload resources and does not add
unrestricted `kms:*` access.

IAM impact is 12 service roles, 12 inline role policies, and one managed
Kinesis producer policy. No Lake Formation resource changes are planned.

## Cost review

The estimated new always-on monthly baseline is about USD 90.32 before small
request/data charges:

| Driver | Monthly estimate |
|---|---:|
| RDS `db.t4g.micro` compute | USD 18.25 |
| RDS gp3 20 GB | USD 2.76 |
| DMS `dms.t3.small` compute | USD 40.88 |
| Secrets Manager interface endpoint, two AZs | USD 14.60 |
| One provisioned Kinesis shard | USD 13.43 |
| One Secrets Manager secret | USD 0.40 |
| Total baseline | USD 90.32 |

Glue, Firehose, Athena, SageMaker training/transform, Bedrock, S3 Vectors, S3,
CloudWatch, KMS requests, and data processing are usage-based. For the tiny V1
fixtures they should be low, but they are not included in the fixed baseline.
The total materially exceeds the approved USD 12/month review threshold.

The lowest-cost V1 execution is to apply, run the real acceptance tests
promptly, and then request a separate destructive cleanup approval for the CDC
and streaming always-on resources. No cleanup is included in this plan.

## Security, rollback, and limitations

- The plan contains no credential value. The generated database password is
  sensitive in local Terraform state and is stored in KMS-encrypted Secrets
  Manager only. Local state is a Human-approved V1 shortcut, not the V3/V4
  target.
- RDS and DMS are private. Glue and DMS reach Secrets Manager through the
  planned two-AZ interface endpoint. No NAT Gateway or public subnet is added.
- Temporary root execution remains the Human-approved V1 exception. The
  service roles are logically separate, but operator/persona least privilege
  remains V3 work.
- RDS has Terraform `prevent_destroy`. A later cleanup requires an intentional
  reviewed Terraform change and explicit destructive approval. The synthetic
  DEV database currently skips a final snapshot.
- QuickSight is excluded. Athena BI can be verified now; QuickSight needs an
  account subscription and edition/cost decision.
- ML labels and RAG documents are synthetic. Results demonstrate integration,
  not business model quality or production policy correctness.

If apply partially fails, retain successfully created resources in state,
correct the routine defect, regenerate the plan, and re-apply. Do not manually
delete or recreate persistent resources. Any architecture, security, or
material cost deviation returns to Human review.

## Verification evidence

- `terraform fmt -recursive -check`: pass
- `terraform validate`: pass
- Python tests: 31 passed
- Python compilation: pass
- Infrastructure static assertions: pass
- Secret/credential scan: pass
- Terraform plan provider validation: pass after correcting the DMS provider
  enum from `test_decoding` to `test-decoding`
- TFLint and Checkov: unavailable locally

No AWS resource-changing operation was executed during this review.
