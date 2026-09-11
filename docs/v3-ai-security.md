# V3 ML and RAG security boundary

## Scope and evidence

This is the AI Engineering support design for V3. It does not change the V2
ML or RAG architecture, create AWS resources, or run Training, Transform,
Glue, ingestion, retrieval-and-generation, or any other billable workload.

The audit used the Terraform source, current DEV Terraform state, and live
read-only AWS API results on 2026-09-12. Live IAM policies and trust policies
matched Terraform state. None of the three audited AI execution roles has an
attached managed policy; each has only its expected inline policy. The current
CLI caller is still account root, confirming the V3 operator-path gap. No ARN in
this document was invented.

Live checks also confirmed that Knowledge Base `AIKVWGQ7FK` is `ACTIVE`, data
source `ZQZTSRBX9Z` is `AVAILABLE`, the S3 Vectors index is KMS-encrypted, and
the documents bucket has all four public-access blocks plus default SSE-KMS.
Its bucket policy contains only explicit deny guardrails for insecure transport
and incorrect explicit encryption; role allows come from IAM. The shared KMS
key policy still delegates its V1 administration and cryptographic actions to
account root. The only current KMS grants are three RDS-scoped grants; no
unexpected ML/RAG grant was present.

## Deployed resource dependencies

### ML

| Purpose | Existing resource | Required relationship |
| --- | --- | --- |
| Human ML operation | Proposed `MLEngineer` persona role | Submits and observes only project Training/Transform jobs, passes only the existing SageMaker execution role, starts only the existing postprocess job, and reads only run artifacts needed for evaluation. |
| SageMaker data-plane execution | `arn:aws:iam::199476069493:role/insurance-dev-claim-fraud-sagemaker-role` | Trusted only by `sagemaker.amazonaws.com`; reads training/inference inputs, writes model/transform artifacts, decrypts/encrypts with the project key, and pulls the AWS-published XGBoost image. |
| Postprocessing | Glue job `insurance-dev-claim-risk-postprocess` using `arn:aws:iam::199476069493:role/insurance-dev-claim-risk-glue-role` | Reads Batch Transform output and claim-ID sidecar and writes the Gold `claim_risk` Iceberg snapshot. MLEngineer passes no role to Glue because `StartJobRun` uses the job's configured role. |
| ML data and artifacts | `s3://aip-insurance-dev-control-dev01/ml/` | Contains prepared train/validation/inference inputs, claim-ID sidecar, model artifacts and transform output. |
| Approved analytical input | `insurance_dev_gold.claim_risk_features` / `s3://aip-insurance-dev-lakehouse-dev01/lakehouse/gold/` | Lake Formation should grant `SELECT` only on the approved feature table, not blanket Gold, Silver or Bronze access. Direct lakehouse S3 access should not be the human role's primary authorization path. |
| Encryption | `arn:aws:kms:ap-southeast-2:199476069493:key/dadd0260-8649-4413-98dc-f2fbc5ebca5c` | Execution roles require scoped cryptographic use. MLEngineer needs decrypt/encrypt only when directly reading or writing the approved `ml/` objects; no KMS administration. |
| Registry metadata | `arn:aws:sagemaker:ap-southeast-2:199476069493:model-package-group/insurance-dev-claim-fraud` | Existing V2 flow does not register a package. V3 must not add registry workflow or permissions merely because the group exists. |

The ML runner actually calls `CreateTrainingJob`, `DescribeTrainingJob`,
`CreateModel`, `CreateTransformJob`, `DescribeTransformJob`, `DeleteModel`,
`StartJobRun`, `GetJobRun`, `ListObjectsV2`, and `GetObject`. These calls define
the operator boundary; the SageMaker execution role separately defines what the
managed compute can access.

### RAG

| Purpose | Existing resource | Required relationship |
| --- | --- | --- |
| Application retrieval | Proposed `RAGApplication` service role | Calls only `bedrock:Retrieve` for Knowledge Base `AIKVWGQ7FK` and/or `bedrock:RetrieveAndGenerate`; invokes only Nova Micro when `RetrieveAndGenerate` requires caller model permission. AWS currently requires `Resource = "*"` for `RetrieveAndGenerate`, so this unavoidable exception must be isolated in its own statement. |
| Knowledge Base | `arn:aws:bedrock:ap-southeast-2:199476069493:knowledge-base/AIKVWGQ7FK` | Uses the existing Bedrock service role and S3 Vectors index. |
| Data source | Knowledge Base `AIKVWGQ7FK`, data source `ZQZTSRBX9Z` | Reads only the approved `rag/approved/` prefix. Ingestion administration belongs to DataEngineer, not RAGApplication. |
| Knowledge Base service role | `arn:aws:iam::199476069493:role/insurance-dev-rag-bedrock-role` | Trusted only by `bedrock.amazonaws.com` with account and Knowledge Base source conditions. Reads approved documents, invokes Titan V2, and manages vectors for ingestion/retrieval. |
| Approved documents | `s3://aip-insurance-dev-documents-dev01/rag/approved/` | Direct access remains with the Bedrock service role. RAGApplication does not need direct S3 permission to answer questions. |
| Embedding model | `arn:aws:bedrock:ap-southeast-2::foundation-model/amazon.titan-embed-text-v2:0` | Invoked by the Knowledge Base service role for ingestion; do not grant it to RAGApplication. |
| Generation model | `arn:aws:bedrock:ap-southeast-2::foundation-model/amazon.nova-micro-v1:0` | Grant `bedrock:InvokeModel` only if required by the tested `RetrieveAndGenerate` caller path. |
| Vector bucket and index | `arn:aws:s3vectors:ap-southeast-2:199476069493:bucket/aip-insurance-dev-vectors-dev01` and `.../index/insurance-rag-index` | Direct vector permissions remain with the Knowledge Base service role. RAGApplication does not need them. |
| Encryption | Same project KMS key as ML | Knowledge Base service role and S3 Vectors integration require scoped use. RAGApplication requires no direct KMS permission for runtime KB retrieval. |

The RAG CLI contains two distinct duties. `sync_documents` calls
`ListIngestionJobs`, `StartIngestionJob`, and `GetIngestionJob`; assign those to
DataEngineer or a controlled ingestion operator. The normal application path
calls `Retrieve` or `RetrieveAndGenerate`; assign only those to RAGApplication.

## Current over-breadth and gaps

1. There are no distinct Terraform-managed `MLEngineer` or `RAGApplication`
   caller roles in the audited V2 state. Root/manual credentials therefore
   supplied the caller-side control-plane permissions during V1/V2 proof.
2. The SageMaker execution role can list the entire lakehouse and control
   buckets. Its object statement also permits `PutObject` throughout
   `lakehouse/gold/*`, although the current managed Training/Transform compute
   uses only `control/ml/*`; Gold publication is performed by the separate Glue
   role. The bucket-level `ListBucket` permissions also lack prefix conditions.
   Live IAM readback confirmed this is the effective policy, not only stale
   Terraform intent.
3. The SageMaker execution role's `kms:GenerateDataKey*` and `kms:ReEncrypt*`
   are broader action patterns than the current S3 input/output path normally
   requires. Retain only the exact operations proven necessary after a real
   non-expensive access check.
4. `ecr:GetAuthorizationToken` and `cloudwatch:PutMetricData` necessarily use
   `Resource = "*"`; the CloudWatch action is correctly constrained to the
   `Insurance/ML` namespace. The XGBoost ECR repository uses a wildcard account
   and repository suffix because AWS owns regional framework images; document
   this exception rather than pretending it is fully resource-specific.
5. The Knowledge Base service role is substantially resource-scoped, but its
   trust `SourceArn` currently accepts any Knowledge Base in the account and
   Region. After the existing KB ARN is known at policy creation, narrow the
   trust to `knowledge-base/AIKVWGQ7FK` if Terraform dependency handling permits
   it without replacement.
6. The Bedrock service role includes vector mutation and deletion actions.
   These are valid for managed ingestion reconciliation, but must not be copied
   to RAGApplication. Likewise, document KMS and Titan permissions belong to
   the service role, not the caller.
7. The shared KMS module currently has no explicit `user_role_arns`; its V1
   account-root delegation permits IAM policies to authorize cryptographic use.
   V3 should explicitly add the exact service/persona principals, validate the
   happy paths, then remove routine root cryptographic/administrative reliance
   without replacing the key.
8. The Glue postprocess service role can read/write/delete across all
   `lakehouse/*`, rather than only the Iceberg locations needed to publish
   `claim_risk`, and can list the full lakehouse/control buckets. Its Glue
   Catalog and CloudWatch Logs statements use `Resource = "*"`; where Glue or
   Logs API limitations require this, isolate and document the wildcard, while
   narrowing S3 prefixes independently.
9. Live IAM readback found no out-of-band managed-policy attachment on the
   SageMaker, ML Glue, or Bedrock roles and no unexpected inline-policy name.
   Live KMS readback found only the expected RDS service grants. This removes
   the earlier inventory uncertainty but does not remove the root-policy gap.

No `Action = "*"`, AdministratorAccess, broad `iam:*`, broad
`secretsmanager:*`, or `iam:PassRole` was found in the audited ML/RAG service
role definitions.

## Minimum MLEngineer boundary

Create a human/workload persona role separate from both managed-service
execution roles. Its trust policy must name the approved non-root operator
session mechanism selected by the Infrastructure Worker; do not trust account
root as its normal runtime path and do not create access keys.

Minimum caller actions for the existing runner:

- SageMaker: `CreateTrainingJob`, `DescribeTrainingJob`, `CreateModel`,
  `CreateTransformJob`, `DescribeTransformJob`, and `DeleteModel`. Limit job and
  model names to `insurance-dev-claim-risk-*` with supported request/resource
  conditions where AWS provides them. Do not grant endpoint, notebook, domain,
  HPO, Feature Store, pipeline, or account-wide administration actions.
- IAM: `iam:PassRole` only for
  `insurance-dev-claim-fraud-sagemaker-role`, conditioned with
  `iam:PassedToService = sagemaker.amazonaws.com`.
- Glue: `glue:StartJobRun` and `glue:GetJobRun` only for
  `insurance-dev-claim-risk-postprocess`.
- S3: list only `control/ml/`; get approved input/output objects and put only
  the prepared-input, model-output, transform-output and audit subpaths required
  by the runner. Do not grant Landing, Bronze, quarantine, documents or audit
  bucket access.
- Lake Formation/Glue Catalog/Athena: `SELECT` and metadata access only for
  `insurance_dev_gold.claim_risk_features` (and `claim_risk` if validation is
  part of the persona workflow), with the existing controlled Athena result
  location. Do not grant raw customer tables or unrestricted Silver/Bronze.
- KMS: `Decrypt` and `DescribeKey` for approved reads; add `Encrypt` and
  `GenerateDataKey` only for approved `control/ml/` writes. Use encryption
  context / ViaService conditions where compatible with S3 and SageMaker.
- Read-only observability: only the job descriptions and project log streams
  needed to diagnose its own runs. No CloudWatch Logs deletion.

Narrow the SageMaker execution role itself to `control/ml/*` and remove its
Gold write. If direct Gold feature reads are not used by managed compute, remove
the lakehouse object access entirely; leave Gold authorization with Lake
Formation for the persona and with the Glue postprocess role for publication.

## Minimum RAGApplication boundary

RAGApplication is a caller/service persona, not the existing Bedrock Knowledge
Base execution role. Until an approved application compute principal exists,
its trust relationship must remain an explicit Infrastructure decision; V3
must not invent Lambda, ECS or another hosting service.

Minimum runtime actions:

- `bedrock:Retrieve` for Knowledge Base `AIKVWGQ7FK`.
- `bedrock:RetrieveAndGenerate` with `Resource = "*"` if the current
  grounded-answer API is retained. The AWS service-authorization model does not
  currently support a Knowledge Base ARN for this action; keep it in a separate
  statement and do not combine it with other broad Bedrock actions.
- `bedrock:InvokeModel` only on Nova Micro if the real caller test proves the
  API evaluates generation-model permission on the caller.

Do not grant RAGApplication S3, S3 Vectors, KMS, Titan embedding,
`StartIngestionJob`, Secrets Manager, RDS, DMS, Glue, Athena, Lake Formation,
or any lakehouse bucket permission. The Knowledge Base service role performs
document, vector and embedding access on behalf of the managed service.

Keep the existing Bedrock service role scoped to the one approved document
prefix, one vector bucket/index, one KMS key and Titan V2. Ingestion lifecycle
actions stay there because Bedrock performs them, while ingestion API calls
belong to DataEngineer.

## Safe positive and negative access tests

Run these only after the Infrastructure Worker creates the persona roles and
the trusted non-root operator can obtain temporary sessions. Use unique test
session names, capture command, principal ARN, timestamp, API/status, request ID
and expected outcome, and never record credentials, document bodies or PII.

### MLEngineer

Positive tests, without starting compute:

1. Assume MLEngineer and confirm `sts:GetCallerIdentity` returns the role.
2. `s3api head-object` an approved prepared feature/input object under
   `aip-insurance-dev-control-dev01/ml/`; expect success.
3. Query only `insurance_dev_gold.claim_risk_features` with Athena using
   `SELECT claim_id, as_of_date ... LIMIT 1`; expect success. This is a small,
   low-cost query and proves the LF grant rather than only IAM policy text.
4. Call `sagemaker:DescribeTrainingJob` on the accepted completed V1 job and
   `glue:GetJobRuns` for the postprocess job; expect success. Do not create a
   new Training or Transform job for an access test.
5. Use IAM policy simulation as an additional, not sole, check that
   `CreateTrainingJob`, `CreateTransformJob`, `DeleteModel`, scoped
   `StartJobRun`, and scoped `PassRole` evaluate to allowed. This avoids cost.

Negative tests:

1. `head-object` against a known Bronze customer object and an approved RAG
   document; expect `AccessDenied`.
2. Athena query selecting customer `name`, `email`, `phone`, `address`, or
   `date_of_birth` from a governed customer table; expect Lake Formation access
   denial before data is returned.
3. `secretsmanager:GetSecretValue` on the RDS source secret ARN; expect denial.
4. Policy-simulate `sagemaker:CreateEndpoint`, `CreateNotebookInstance`, and
   `iam:PassRole` for any role other than the one SageMaker execution role;
   expect explicit or implicit denial.
5. Attempt `kms:Decrypt` using unrelated ciphertext/key metadata, without
   printing plaintext; expect denial. Do not alter a key or grant.

### RAGApplication

Positive tests:

1. Assume RAGApplication and confirm its caller identity.
2. Call `bedrock-agent-runtime retrieve` for Knowledge Base `AIKVWGQ7FK` with
   one fixed non-PII insurance question and one result; expect a non-empty
   result with an `s3://.../rag/approved/` source URI. This is cheaper than a
   full answer-generation test.
3. If `RetrieveAndGenerate` is part of acceptance, run exactly one fixed
   question with Nova Micro and require a non-empty citation. Do not sync or
   re-embed documents.

Negative tests:

1. `s3api head-object` on an approved document, a Silver customer object and a
   Gold business object; all direct S3 calls should be denied. The positive KB
   retrieval proves the service-mediated path still works.
2. Call `bedrock-agent start-ingestion-job`; expect denial.
3. Call S3 Vectors `GetIndex`, `QueryVectors`, or `PutVectors` directly; expect
   denial.
4. Call Titan V2 `InvokeModel` directly; expect denial. If Nova Micro direct
   invocation was granted for `RetrieveAndGenerate`, confirm another foundation
   model is denied.
5. Request the RDS secret and call Athena/Glue/RDS/DMS read operations; expect
   denial.
6. Attempt decrypt with the project KMS key directly; expect denial because
   application retrieval is service mediated.

Negative tests must use read/head/query/simulation operations only. Do not
upload objects, mutate vectors, change grants, stop jobs, or modify shared data
to manufacture a denial. A failed call is accepted only when its error code is
authorization-related; `NotFound`, invalid parameters, throttling or quota
errors are not evidence of access enforcement.

## V2 compatibility safeguards

- Keep the existing SageMaker and Bedrock service roles separate from the new
  personas; never replace a service trust policy with a human trust policy.
- Apply additive persona/Lake Formation grants first, execute positive tests,
  then remove broad root delegation and excess service-role permissions.
- Reuse the existing key, buckets, Knowledge Base, vector index, models and Glue
  job. No resource replacement is necessary for this design.
- Do not rerun Training, Transform or KB ingestion merely to validate IAM.
- Before policy tightening, preserve a Terraform plan with zero destroys and
  inspect role/KMS/LF diffs. After apply, repeat one cheap positive and all safe
  negative tests under the new roles.
- If live discovery reveals an out-of-band managed policy, KMS grant, bucket
  grant, or SCP not represented in Terraform, stop that tightening step and
  reconcile the inventory rather than deleting it blindly.

Expected fixed recurring cost for these IAM/Lake Formation/policy changes is
USD 0. The optional Athena `LIMIT 1`, one KB retrieval, and one grounded answer
produce only minimal usage-based validation cost.
