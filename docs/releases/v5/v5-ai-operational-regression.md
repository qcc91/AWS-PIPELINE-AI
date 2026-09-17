# V5 AI Operational Regression

## Scope

This package verifies the accepted ML and RAG operational contracts without
changing their architecture or creating billable workloads. It adds no model,
endpoint, notebook, ingestion, persistent compute, data source, or vector
technology. The detailed operator procedure is in
`docs/runbooks/ml-rag-operations.md`.

## Regression coverage

The focused ML checks prove that identical claim IDs, probabilities, model
version, run ID, and timestamp produce identical Gold-contract rows. Static
contract checks confirm that the deployed Glue postprocessor rejects row-count
mismatch, duplicate/missing identities, missing lineage, and invalid
probabilities before using Iceberg `createOrReplace`. Append publication is
explicitly prohibited by the regression.

The focused RAG checks execute the CLI decision path with a local approved
document and an already-persisted identical manifest. They prove that the
effective sync flag becomes false, the audit contains `UNCHANGED_SKIPPED`, and
no ingestion start event occurs. A simulated terminal ingestion failure also
proves that failure reasons are preserved and are not mistaken for successful
reconciliation.

## Existing real baseline reused

- ML: the accepted V1/V2 proof has 120 predictions and 120 distinct claims,
  non-null run/dataset lineage, and probability range `0.36053–0.60398` after
  replaying the same Transform output twice. No new Training, Transform, or
  Glue job is required for this V5 regression.
- RAG: ingestion `JPIWFL7ZWT` reconciled two scanned, zero failed, and zero
  new/modified documents; the immediate identical-manifest run recorded
  `UNCHANGED_SKIPPED`. Three fixed questions previously returned approved S3
  citations. No new ingestion or generated answer is required here.

## Optional real checks

Only after the Manager confirms a valid non-root session, run read-only status
calls for the accepted SageMaker jobs, latest Glue runs, Knowledge Base, data
source, and ingestion history. One Athena aggregate or one KB retrieval may be
used only if the existing evidence is stale or inconsistent. Do not rerun
Training, Transform, postprocessing, ingestion, or generation for routine V5
acceptance.

At package execution time, the configured Human, Operator, and
TerraformExecution CLI sessions were expired. Consequently, no live AWS call
was treated as fresh evidence and no root fallback was used. The accepted
V1/V2 real baseline above remains the referenced runtime evidence.

## Cost, security, and limitations

Local regression and read-only status APIs have no recurring cost. Optional
Athena/retrieval checks are usage-based and should remain negligible, but are
not needed when the accepted evidence is current. The checks use no credentials
and persist no PII, document content, retrieved chunks, or generated answers.

This is operational regression, not model monitoring: it does not measure live
feature drift, prediction drift, calibration drift, retrieval relevance over a
large benchmark, or automated retraining. Those capabilities would add scope
and possible ongoing cost and therefore require a later architecture decision.
