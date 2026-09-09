# V1 RAG happy-path implementation

## Scope

This package defines the smallest non-agentic RAG path: approved synthetic
insurance documents in the existing DEV `documents` bucket, one Bedrock
Knowledge Base, one S3 Vectors index, an S3 data source, ingestion sync, and
`RetrieveAndGenerate` responses that retain source citations. No customer PII,
OpenSearch, agents, or persistent inference endpoint is included.

The module is connected to `terraform/environments/dev` and has been applied in
DEV. The deployed Knowledge Base is `AIKVWGQ7FK`, its approved-document data
source is `ZQZTSRBX9Z`, and its S3 Vectors index is `insurance-rag-index` in
`aip-insurance-dev-vectors-dev01`.

Runtime ingestion was attempted with bounded retries and consistently failed
when Bedrock called Titan Text Embeddings V2 with HTTP 429 `Too many requests`.
The Knowledge Base remains `ACTIVE`, but retrieval acceptance cannot be claimed
until ingestion succeeds. Do not retry until model quota/access preflight shows
the account can invoke the embedding model.

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

The module uploads only the two reviewed synthetic documents under
`rag/approved/` with source hashes and SSE-KMS. From the same authenticated
execution context used for AWS operations, run:

```powershell
aws s3api head-object --bucket aip-insurance-dev-documents-dev01 --key rag/approved/claims-handling-guide.md --region ap-southeast-2
aws s3api head-object --bucket aip-insurance-dev-documents-dev01 --key rag/approved/product-terms.md --region ap-southeast-2
aws s3vectors get-index --vector-bucket-name aip-insurance-dev-vectors-dev01 --index-name insurance-rag-index --region ap-southeast-2
python -m src.rag.run_rag --knowledge-base-id AIKVWGQ7FK --data-source-id ZQZTSRBX9Z --question "What is the waiting period for eligible accidental-damage claims?" --region ap-southeast-2 --timeout 900
```

The CLI starts ingestion, waits for `COMPLETE`, and calls
`RetrieveAndGenerate` with the explicit Nova Micro ARN. Runtime acceptance
requires a grounded fourteen-calendar-day answer and a source URI for
`claims-handling-guide.md`; resource existence or ingestion completion alone
is insufficient. The CLI rejects empty or uncited responses and reports
Bedrock ingestion failure reasons. Deleting or replacing a document requires a
subsequent ingestion sync and a stale-chunk check.

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
Actual ingestion/retrieval remains the authenticated DEV acceptance test once
the account-level embedding-model blocker is cleared.
