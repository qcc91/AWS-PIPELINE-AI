# Iterative delivery roadmap

The final V5 architecture and requirements remain unchanged. Delivery uses one
cumulative codebase and implements only the currently authorized version.

## V1 — End-to-end happy path (accepted and tagged)

Prove the complete DEV path at small scale: Terraform infrastructure; S3, KMS,
minimal networking, basic IAM and Glue Catalog; CSV batch through EventBridge,
Step Functions and Glue; RDS PostgreSQL full load/CDC through DMS; Python events
with the Kinesis/Firehose branch documented as account-limited; Bronze, Silver and Gold Iceberg; Athena and
QuickSight; SageMaker XGBoost batch inference; and Bedrock Knowledge Bases with
S3 Vectors. The demo must use real sample data and cover customer, product,
policy, claim, payment and event data plus the approved Gold datasets.

V1 proves functionality. It does not require full production hardening.

## V2 — Reliability and data quality (authorized)

Retire Streaming by Human decision without replacement. Add Bronze/Silver/Gold
operational boundaries, bounded retries, idempotency, duplicate handling,
replay safety, DQ gates, quarantine, the standard audit/run envelope,
reconciliation, failure paths and recovery proof for Batch, CDC, ML, and RAG.

## V3 — Security and governance

Complete least-privilege IAM, Lake Formation role and PII controls, approved
RAG document-only access, KMS refinement, Secrets Manager, S3 and CloudTrail
controls, and negative access tests.

## V4 — CI/CD and environment automation

Complete separate DEV/PROD remote state and environments, GitHub integration,
CodePipeline/CodeBuild, PR validation, DEV automation and broader unit, data,
integration, E2E and security tests. PROD remains Human-approved only.

## V5 — Production readiness

Complete observability and alerting, service and DQ metrics, intentional
failure/recovery/replay tests, retention/cost/security reviews, runbooks,
production-readiness documentation and final E2E validation.

## Delivery rule

Implement only the currently authorized version. V2 must not introduce V3
least-privilege governance, V4 CI/CD, or V5 production-readiness scope.

Temporary root execution is a Human-approved V1 shortcut for DEV Terraform
planning and deployment only. No root credential may be stored or printed, and
no access key may be created. Proper least-privilege IAM separation remains a
required V3 outcome.
