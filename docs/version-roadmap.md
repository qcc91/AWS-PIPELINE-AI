# Iterative delivery roadmap

The final V5 architecture and requirements remain unchanged. Delivery uses one
cumulative codebase and implements only the currently authorized version.

## V1 — End-to-end happy path (authorized)

Prove the complete DEV path at small scale: Terraform infrastructure; S3, KMS,
minimal networking, basic IAM and Glue Catalog; CSV batch through EventBridge,
Step Functions and Glue; RDS PostgreSQL full load/CDC through DMS; Python events
through Kinesis and Firehose; Bronze, Silver and Gold Iceberg; Athena and
QuickSight; SageMaker XGBoost batch inference; and Bedrock Knowledge Bases with
S3 Vectors. The demo must use real sample data and cover customer, product,
policy, claim, payment and event data plus the approved Gold datasets.

V1 proves functionality. It does not require full production hardening.

## V2 — Reliability and data quality

Add bounded retries, idempotency, duplicate handling, replay safety, Glue Data
Quality gates, quarantine, the standard audit/run envelope, reconciliation,
failure paths and recovery proof.

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

Design V1 choices so they do not unnecessarily block V2–V5, but do not add
later-version complexity unless V1 technically requires it. Correct existing
hardening remains in place without becoming a V1 perfection task.
