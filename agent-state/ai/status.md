# AI Engineering Worker Status

## V5 operational regression (2026-09-15)

- Added focused, local ML replay-contract and RAG unchanged-sync regression
  coverage; no Training, Transform, Glue, ingestion, retrieval, or generation
  workload was started.
- ML checks protect deterministic output, pre-publication reconciliation,
  unique identity/lineage/probability validation, and Iceberg snapshot
  replacement rather than append.
- RAG checks prove an identical manifest produces `UNCHANGED_SKIPPED` with no
  ingestion start and that terminal failure reasons remain observable.
- Added the ML/RAG operations runbook with read-only diagnosis, bounded-retry,
  recovery, escalation, cost, and security guidance.
- Architecture is unchanged and no persistent compute or recurring cost was
  introduced.

## V3 completion (2026-09-13)

- MLEngineer is restricted to approved Gold feature/prediction tables; real
  Gold ALLOW and Silver/Secrets DENY tests passed.
- RAGApplication real Knowledge Base retrieval passed while direct Lakehouse
  access was denied. Managed-service execution roles remain separate.

- Current package: V2 ML and RAG reliability — COMPLETE.
- ML: validates nulls, domains, unique claim IDs, labels, as-of semantics and class balance; emits deterministic dataset version and structured Training/Transform audit; postprocessing validates prediction counts and publishes an idempotent snapshot with model/dataset/run lineage.
- RAG: stable per-document SHA-256 identity/version, empty/malformed validation, manifest diff, unchanged-sync skip, non-overlap guard, bounded transient/429 retry, ingestion reconciliation and citation validation.
- Real RAG proof: document validation 2 valid/0 rejected; ingestion `JPIWFL7ZWT` scanned 2/failed 0/indexed-or-modified 0 and reconciled 2 unchanged; immediate repeat recorded `UNCHANGED_SKIPPED` without another ingestion job.
- Three fixed Nova Micro questions returned non-empty grounded answers with S3 citations.
- Existing architecture remains SageMaker XGBoost batch and Bedrock KB + Titan V2 + S3 Vectors. No endpoint, notebook, new model, subscription or recurring resource was introduced.
- Real ML proof: accepted transform output reprocessed twice; both Glue runs succeeded and Athena confirmed 120 rows/120 unique claims, zero missing lineage and stable probability range.

## V3 support package

- ML/RAG security boundary audit and least-privilege persona design completed in `docs/v3-ai-security.md`.
- Existing managed-service roles remain separate from proposed caller personas: MLEngineer orchestrates only the approved batch workflow; RAGApplication uses only service-mediated Knowledge Base retrieval.
- No AWS resources or Terraform were changed and no billable workload was run. Live IAM/KMS/S3/Bedrock readback matched the current Terraform state, found no managed-policy attachments or unexpected AI KMS grants, and confirmed root is still the current CLI caller.

Last updated: 2026-09-15.
