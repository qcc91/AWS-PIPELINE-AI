# ML and RAG Operations Runbook

## Purpose and safety boundary

This runbook operates the accepted batch ML and RAG paths without adding AI
features or persistent compute. Prefer local tests and read-only AWS inspection.
Do not start SageMaker Training, Batch Transform, Glue postprocessing, or a
Knowledge Base ingestion job merely to prove availability. Do not log customer
PII, document bodies, credentials, model payloads, or retrieved chunks.

## ML batch operations

### Healthy signals

- Training and Transform jobs have terminal status `Completed`.
- Glue postprocessing has terminal status `SUCCEEDED`.
- The audit trail contains `training`, `transform`, `postprocess`, and
  `model_cleanup` events tied to one `model_run_id` and `dataset_version`.
- Gold `claim_risk` has equal row and distinct-`claim_id` counts, probabilities
  in `[0,1]`, non-null lineage, and one current row per claim.
- Replaying the same accepted Transform output converges to the same Iceberg
  snapshot cardinality because publication is `createOrReplace`, not append.

### Read-only diagnosis

Use the non-root role chain and substitute an already-known job name. These
commands do not create compute:

```powershell
aws sagemaker describe-training-job --region ap-southeast-2 --training-job-name <job>
aws sagemaker describe-transform-job --region ap-southeast-2 --transform-job-name <job>
aws glue get-job-runs --region ap-southeast-2 --job-name insurance-dev-claim-risk-postprocess --max-results 5
```

Use Athena only when the normal authorization path and workgroup are available:

```sql
SELECT
  count(*) AS rows,
  count(DISTINCT claim_id) AS unique_claims,
  sum(CASE WHEN model_run_id IS NULL OR dataset_version IS NULL THEN 1 ELSE 0 END) AS missing_lineage,
  min(high_risk_probability) AS min_probability,
  max(high_risk_probability) AS max_probability
FROM insurance_dev_gold.claim_risk;
```

### Failure signals and actions

| Signal | Meaning | Safe action |
| --- | --- | --- |
| Training/Transform `Failed` or `Stopped` | Managed job did not produce an accepted artifact | Capture job name, status, failure reason and CloudWatch log reference. Correct deterministic input/IAM errors before a rerun; retry only documented transient service errors. |
| Missing or non-finite `validation:auc` | Model-quality contract failed | Reject the run. Inspect split class balance and input channels; do not promote the artifact. |
| Prediction/manifest count mismatch | Predictions cannot be joined safely | Stop publication. Verify that Transform input and claim-ID sidecar share the same dataset version and ordering. |
| Duplicate claim IDs, missing lineage, or probability outside `[0,1]` | Gold contract violation | Keep the prior Gold snapshot. Correct the artifact/manifest and rerun postprocessing only after validation. |
| Model cleanup failure | Temporary SageMaker Model may remain | Inspect and delete only the exact transient Model after confirming no Transform job uses it; do not delete model artifacts or accepted Gold data. |
| Athena row count differs after replay | Idempotency regression | Stop further replays, preserve run IDs and compare Iceberg snapshot history. Do not rewrite or delete snapshots during diagnosis. |

## RAG operations

### Healthy signals

- The Knowledge Base is `ACTIVE` and the data source is `AVAILABLE`.
- The most recent required ingestion is `COMPLETE`, with discovered/scanned
  counts reconciled and zero failed documents.
- Re-running against the identical manifest records `UNCHANGED_SKIPPED` and
  does not call `StartIngestionJob`.
- Retrieval returns a non-empty answer and at least one `s3://.../rag/approved/`
  citation. Direct document/vector access remains denied to RAGApplication.

### Read-only diagnosis

```powershell
aws bedrock-agent get-knowledge-base --region ap-southeast-2 --knowledge-base-id AIKVWGQ7FK
aws bedrock-agent get-data-source --region ap-southeast-2 --knowledge-base-id AIKVWGQ7FK --data-source-id ZQZTSRBX9Z
aws bedrock-agent list-ingestion-jobs --region ap-southeast-2 --knowledge-base-id AIKVWGQ7FK --data-source-id ZQZTSRBX9Z --max-results 10
```

Do not repeatedly run retrieval or ingestion when the account is throttled.
The Service Quotas console showing Titan RPM `0` is a known display
inconsistency for this account; use the actual API outcome and the recorded AWS
Support finding, not the displayed value alone.

### Failure signals and actions

| Signal | Meaning | Safe action |
| --- | --- | --- |
| `OVERLAP_BLOCKED` | Another ingestion is active | Wait for that exact job to reach a terminal state. Do not start a second job. |
| `START_FAILED` / `POLL_FAILED` | API, authorization, or transient service failure | Record AWS error code/request ID. Retry only a recognized transient error, bounded to three attempts; fix access errors rather than retrying. |
| Ingestion `FAILED` / `STOPPED` | Corpus was not reconciled | Read failure reasons and statistics; validate UTF-8, non-empty approved files and manifest changes locally before one controlled retry. |
| `TIMED_OUT` | Client stopped waiting; job state is unknown | Inspect the same job ID read-only. Never infer failure or launch an overlapping job. |
| `GROUNDING_FAILED` or missing approved S3 citation | Answer is not acceptable | Reject the answer, retain the question and metadata without answer text, verify KB/data-source state, and inspect retrieval with a single fixed non-PII question. |
| HTTP 429 / throttling | Bedrock capacity is temporarily constrained | Honor exponential backoff, stop after three attempts, and wait before a later operator-controlled check. Do not request quota or loop ingestion for the two-document corpus. |

## Escalation and recovery evidence

Escalate when the same bounded retry is exhausted, a security denial contradicts
the V3 policy, an Iceberg snapshot would need destructive repair, or recovery
requires a new service/cost. Record UTC time, environment, caller role, source
revision, model/dataset/run or ingestion IDs, terminal status, sanitized error
code, reconciliation counts, and the recovery decision. Never record temporary
credentials, raw PII, document content, or generated answers.
