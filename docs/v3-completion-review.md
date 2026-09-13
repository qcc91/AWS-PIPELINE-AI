# V3 Security + Governance Completion Review

Status: implementation complete; awaiting Human acceptance. Date: 2026-09-13.

## Identity and bootstrap boundary

The console-only `insurance-dev-local-operator` IAM user has MFA, no access
key, no AdministratorAccess, and no direct project-data permission. A real
pre-enrolment AssumeRole attempt was denied. After MFA login, the verified
chain is Human -> `insurance-dev-operator-role` ->
`insurance-dev-terraform-execution-role`. Human and Operator direct S3 data
tests were denied.

Bootstrap identities, bootstrap state and its KMS key are separately managed.
TerraformExecution can use only `foundation/terraform.tfstate` and its lock;
it cannot access `bootstrap/terraform.tfstate`, administer the Human/Operator/
itself, or administer the state-key policy. Account root remains only the
bootstrap/recovery KMS administrator and was logged out after the one required
policy update.

## Governance and hardening

- Separate DataEngineer, Analyst, MLEngineer, RAGApplication and Lake Formation
  registration roles are deployed without managed Administrator policies.
- Lakehouse and control locations are registered. Analyst receives ten approved
  non-PII Gold tables; MLEngineer receives only `claim_risk_features` and
  `claim_risk`; RAGApplication has no Lake Formation grant.
- `policy_performance` was removed from Analyst whole-table access because its
  `policy_id` is re-identifiable. Direct Landing/Lakehouse access is denied to
  restricted personas; access to approved tables is mediated by Lake Formation.
- Project buckets retain public-access blocking, TLS-only policies and KMS
  encryption. Secret access is limited to the approved DataEngineer/workload
  paths. Platform, audit and state KMS administration boundaries are separate.
- CloudTrail is logging and log-file integrity validation is enabled.

## Real access evidence

- DataEngineer Glue Gold catalog: ALLOW.
- Analyst Gold `claim_daily_summary`: SUCCEEDED (`12ede556-58df-44ce-9bfc-45c4d8fb9fc7`).
- Analyst Silver `customers`: DENY (`7d9d6bcc-4503-4bf6-a004-0564dbc6d5ed`).
- MLEngineer Gold `claim_risk_features`: SUCCEEDED (`e172208a-440d-4ef1-b58f-5fa205a18eb2`).
- MLEngineer Silver `customers`: DENY (`dbe955bb-599e-4ac6-88a1-078acc631c50`).
- Analyst and MLEngineer Secrets Manager reads: DENY.
- RAGApplication approved Knowledge Base retrieval: ALLOW; direct Lakehouse: DENY.

## Regression, drift and cost

The latest Batch and CDC Step Functions executions remain `SUCCEEDED`; RAG
retrieval and the approved BI/ML Athena paths pass. The DMS task is currently
`failed`, but its recorded stop was 2026-09-11, before V3 began; its full load
completed 5/5 tables with zero table errors. This is a pre-existing operational
limitation, not V3 drift, and was not blindly restarted during security work.

Terraform fmt and DEV/PROD validation pass. The final non-root DEV Foundation
refresh plan exits 0 with no changes. The V2/V3 Data/ML/RAG suite reports
`89 passed`. V3 adds IAM/Lake Formation policy objects and configuration-only
hardening; there is no new continuously running service and expected incremental
recurring cost is effectively USD 0, excluding negligible Athena/RAG validation
requests and normal CloudTrail/S3/KMS usage.

V4, V5, PROD deployment and a `v3.0-governed` tag were not started.
