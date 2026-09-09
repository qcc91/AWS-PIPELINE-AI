# V1 RAG happy-path implementation

## Scope

This package defines the smallest non-agentic RAG path: approved synthetic
insurance documents in the existing DEV `documents` bucket, one Bedrock
Knowledge Base, one S3 Vectors index, an S3 data source, ingestion sync, and
`RetrieveAndGenerate` responses that retain source citations. No customer PII,
OpenSearch, agents, or persistent inference endpoint is included.

The module is connected to `terraform/environments/dev` for a unified V1 plan.
It remains unapplied until the relevant Human Terraform plan gate.

## Mandatory Sydney discovery (read-only)

Run with the intended non-root identity and explicit region before planning:

```powershell
aws sts get-caller-identity --region ap-southeast-2
aws bedrock list-foundation-models --region ap-southeast-2 --by-output-modality TEXT
aws s3vectors list-vector-buckets --region ap-southeast-2
```

Authenticated read-only discovery completed in `ap-southeast-2`: S3 Vectors
API is available, `amazon.titan-embed-text-v2:0` is available at
`arn:aws:bedrock:ap-southeast-2::foundation-model/amazon.titan-embed-text-v2:0`
with 1024 dimensions, and `amazon.nova-micro-v1:0` is available for generation
at `arn:aws:bedrock:ap-southeast-2::foundation-model/amazon.nova-micro-v1:0`.
Record the discovery output with the plan because model access and quotas can
change. If a later check shows a missing capability, return
`ARCHITECTURE_DECISION_REQUIRED`; never silently use a second region or
OpenSearch.

## Terraform inputs and flow

`terraform/modules/rag` requires a discovered `embedding_model_arn` and its
`embedding_dimensions`; the S3 Vectors index is `float32`/cosine and its
dimension must exactly match the model. It creates a KMS-encrypted vector
bucket/index, Bedrock service role scoped to the approved S3 prefix and index,
the KB, and fixed-size chunking (300 tokens, 10% overlap). Use the existing
documents bucket KMS key. The module is region-locked to `ap-southeast-2`.

After an approved apply, the module uploads only the two reviewed synthetic
documents under `rag/approved/` with source hashes and SSE-KMS. Run
`python -m src.rag.run_rag --knowledge-base-id <id> --data-source-id <id>
--question "What is the waiting period?"` to start ingestion, wait for
`COMPLETE`, and call `RetrieveAndGenerate` with the explicit Nova Micro ARN.
The CLI rejects responses that fail citation validation. Deleting or replacing
a document requires a subsequent ingestion sync and a stale-chunk check.

## IAM, security and cost

The Bedrock role can list/read only the approved prefix, decrypt the existing
documents KMS key, invoke only the selected embedding model, and use only the
created vector index. S3 Block Public Access, TLS-only, SSE-KMS, and versioning
come from the existing documents bucket module. Do not log document bodies or
PII. Generation-model invocation belongs to the caller role and must be added
as a separately reviewed least-privilege permission when the chosen model is
discovered.

Costs are usage-based: document embedding/ingestion, vector storage and query,
and generation tokens. The small synthetic corpus avoids continuous compute;
estimate with measured token counts before Gate 2 and keep a budget threshold.

## Local verification

```powershell
pytest -q tests/rag
terraform -chdir=terraform/modules/rag fmt -check
```

The local citation helper tests the required invariant that a response has a
non-empty answer, at least one `s3://` source, and all expected source URIs.
Actual ingestion/retrieval is intentionally an authenticated DEV integration
test after the plan approval gate.
