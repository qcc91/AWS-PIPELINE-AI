# V2 AI Reliability

## Scope and boundary

V2 keeps the accepted V1 AI architectures unchanged. Claim risk remains the
point-in-time Gold/Silver feature dataset followed by one SageMaker XGBoost
Training Job, one Batch Transform Job, and Gold `claim_risk`. RAG remains S3,
Bedrock Knowledge Bases, Titan Text Embeddings V2, S3 Vectors, and grounded
Nova Micro answers. This package does not add Feature Store, Model Registry,
HPO, endpoints, automatic retraining, reranking, hybrid search, agents, another
embedding model, or an external vector database.

## ML reliability contract

Dataset preparation now fails before SageMaker submission when any of these
conditions is observed:

- an empty dataset, null/duplicate `claim_id`, or a label outside `{0,1}`;
- a missing, non-finite, or negative feature where non-negative values are the
  business contract;
- a missing categorical feature;
- a dataset or chronological split without both target classes;
- an invalid submission/as-of date or an `as_of_date` after claim submission;
- a post-submission field in the explicit feature contract.

The feature matrix still excludes approved/paid amounts, final claim status,
outcome severity, investigation result, settlement duration, and update
timestamps. The original target definition remains a future synthetic
high-severity/high-cost outcome after submission; it is never a model feature.

Each prepared dataset receives an order-independent
`claim-risk-v2-<sha256-prefix>` version. `metadata.json` records preparation
time, dataset version, row/unique counts, class distribution, feature count,
as-of range, leakage result, split counts, and feature coverage. The prediction
sidecar carries `claim_id`, `as_of_date`, `feature_version`, `dataset_version`,
split, and label.

Training, Transform, postprocessing, and temporary-model cleanup emit
timestamped stage audit events keyed by `model_run_id`. Training/Transform
terminal failures retain job name, status, and reason. Only recognized
transient API failures are retried, at most three attempts with exponential
backoff. Deterministic validation and model-quality failures are not retried.

Prediction publication requires equal manifest/output counts, unique claims,
and finite probabilities in `[0,1]`. Gold output adds `model_run_id` and
`dataset_version`. Reprocessing the same run validates the same business keys
and deterministically replaces the current `claim_risk` snapshot rather than
appending duplicates.

## RAG reliability contract

Document source location is the stable identity. SHA-256 of the exact bytes is
the content version. Before synchronization, approved documents are decoded as
UTF-8 and rejected if empty, malformed, NUL-containing, or too short to contain
meaningful text. Rejected files receive a trace record with source and failure
reason and are not sent to the Knowledge Base.

The manifest comparison classifies documents as added, changed, unchanged, or
deleted. When all identities and hashes are unchanged, `--sync` is converted
to an audited `UNCHANGED_SKIPPED` operation, so no unnecessary ingestion job is
started. Otherwise, active-job detection still prevents overlap. Start/poll
and retrieval calls retry only explicit transient Bedrock errors, including
HTTP 429 throttling, for at most three exponentially delayed attempts.

Ingestion audit records the job ID, terminal state, failure reasons, Bedrock
statistics, and reconciliation:

`documents discovered = scanned`, with `documents failed = 0` for success.

An unchanged Bedrock synchronization may legitimately scan documents while
indexing zero new/modified documents. That outcome is recorded as unchanged or
skipped, not treated as a failure.

The fixed V2 smoke questions remain:

1. waiting period for eligible accidental-damage claims;
2. reimbursed repair costs and applicable deduction;
3. information required at first notice of loss.

Answers must remain non-empty and carry at least one S3 citation.

## Evidence completed in this work package

- Focused ML/RAG tests: `38 passed`.
- Python compilation: passed for all changed runtime modules and Glue scripts.
- Empty/malformed document rejection, stable hashes, unchanged-manifest
  classification, bounded 429 retry, ingestion reconciliation, overlap guard,
  ML invalid/null/duplicate/label/as-of rejection, deterministic dataset
  version, and structured Training/Transform failures are covered locally.
- The approved local corpus contains two valid documents:
  - `claims-handling-guide.md` SHA-256
    `D3C6243C25E4F1A4E1DAD5D064B8CDEAE98DBAA130ADF0CCB5DFF46A11C17AD2`;
  - `product-terms.md` SHA-256
    `7EF4C56A143BB0100F33523DDC0C4DD6EF79C8021F1996972BDDA5A0F8FA2E9A`.
- Read-only AWS verification on 2026-09-11 confirmed ingestion job
  `U0DDU3DXFT` remains `COMPLETE`: two scanned, two newly indexed, zero failed.
  This is the V1/V2 baseline, not a newly started ingestion.
- AWS Support-confirmed Titan limits remain 6,000 RPM and 300,000 TPM. The
  Service Quotas zero display is not reopened and no increase is requested.

## Real AWS validation

- Athena feature query `18dcd026-e308-4874-b4bd-da02ccbfdfe4` confirmed 120
  unique rows, class balance 39 positive/81 negative and zero negative-amount or
  future-incident violations. The accepted inference/identity artifact pair was
  assigned stable version `claim-risk-v2-af2df383c20496f5`.
- The accepted V1 Batch Transform output was reprocessed twice without new
  training or transform compute. Glue runs
  `jr_98e2f8f9080a3977ecda896ba54b6d7aa187bfc3ee0a8f631636855f44821ae6`
  and `jr_8497b9ba268bf27a4ba9c196ff9ea6b915a8f3d691a2eb217b25d82f41d8c0fa`
  both succeeded. Athena query `41dd000f-3a35-400e-acd4-63f91c493738`
  confirmed 120 rows, 120 unique claims, zero missing lineage and probability
  range `0.36053–0.60398` after the second run.
- The two approved documents validated as 2 valid/0 rejected. One traceable
  ingestion `JPIWFL7ZWT` scanned 2, failed 0, indexed/modified 0 and reconciled
  both as unchanged. Repeating the same manifest recorded
  `UNCHANGED_SKIPPED` and started no ingestion job.
- All three fixed Nova Micro questions returned non-empty grounded answers and
  S3 citations to `claims-handling-guide.md` and/or `product-terms.md`.
- Bounded transient/429 retry and overlap rejection are covered in the focused
  suite; no deliberate throttling or overlapping paid workload was created.

These validations reused existing on-demand resources and added no recurring
cost, endpoint, notebook, training job, transform job, subscription or model.

The V2 sync invocation must include all trace inputs:

```powershell
python -m src.rag.run_rag `
  --knowledge-base-id AIKVWGQ7FK `
  --data-source-id ZQZTSRBX9Z `
  --question "What is the waiting period for eligible accidental-damage claims?" `
  --document-dir documents/rag/approved `
  --document-identity-prefix s3://aip-insurance-dev-documents-dev01/rag/approved/ `
  --manifest "$env:TEMP/aip-v2-rag-document-manifest.json" `
  --audit-output "$env:TEMP/aip-v2-rag-ingestion-audit.json" `
  --sync
```

The manifest/audit locations are runtime artifacts and must not be committed.

## Deferred beyond V2

Feature Store, Registry, HPO, endpoints, automated retraining, model monitoring,
reranking, hybrid retrieval, agentic RAG, multi-model embeddings, and large
evaluation frameworks remain explicitly deferred to later approved versions.
