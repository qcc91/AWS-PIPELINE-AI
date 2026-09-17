# V1 consolidated completion review

Date: 2026-09-10

Region: `ap-southeast-2`

Account plan: `FREE`

## Package status

| Path | Status | Runtime evidence |
|---|---|---|
| Infrastructure Foundation | COMPLETE | DEV bootstrap/foundation deployed and Terraform refresh verified |
| Batch / file ingestion | COMPLETE | Landing -> EventBridge -> Step Functions -> Glue -> Bronze/Silver/Gold Iceberg -> Athena |
| CDC / PostgreSQL | COMPLETE | RDS -> DMS full load/CDC -> S3 -> Glue/Iceberg -> Athena insert/update/delete proof |
| Traditional BI / Athena | COMPLETE | Gold queries and shared BI/ML marts validated |
| QuickSight | INTENTIONALLY DEFERRED | Account is not subscribed; no subscription was created for V1 |
| ML | COMPLETE | SageMaker Training, Batch Transform, Glue Gold publication and Athena validation |
| RAG | COMPLETE | Titan V2 ingestion, S3 Vectors, retrieval, grounded generation and S3 citations |
| Streaming | ACCOUNT-LIMITED | FREE account returns `SubscriptionRequiredException` for Kinesis and Firehose |

## ML result

- Feature dataset: 120 point-in-time Gold `claim_risk_features` rows and 54
  encoded features; chronological split 72 train / 24 validation / 24 test.
- Target: `high_risk_claim`, derived from future synthetic severity/high-cost
  outcome. Approved/paid amounts, final status, investigation outcomes,
  settlement duration, and other post-submission fields were excluded.
- Final Training Job: `insurance-dev-claim-risk-v1-20260910-061552-r2`,
  `Completed`, one `ml.m5.large`; Validation AUC `0.65556`.
- Independent Test: AUC `0.62222`, log loss `0.65632`, accuracy `0.625`.
- Batch Transform:
  `insurance-dev-claim-risk-v1-20260910-061552-r2-transform`, `Completed`, 120
  predictions. Gold `claim_risk` has 120 distinct claims and no null
  probabilities.
- The transient SageMaker Model was deleted; no endpoint or notebook exists.
- Known V1 limits: small synthetic data, training overfit, weak calibration,
  and all observations currently map to the broad MEDIUM risk band. These are
  documented, not tuned away.

## RAG result

- AWS Support case: `178899964200695`.
- Correct Titan V2 backend quota: 6,000 RPM / 300,000 TPM. Service Quotas' zero
  display is inconsistent; prior 429s were real transient ingestion throttling.
- Mitigation: confirm no active job, make sync opt-in, refuse overlapping syncs,
  and perform one controlled ingestion. No quota increase was requested.
- Ingestion job `U0DDU3DXFT`: `COMPLETE`; 2 scanned, 2 new indexed, 0 failed.
- Knowledge Base `AIKVWGQ7FK`: `ACTIVE`; Titan Text Embeddings V2, 1024
  dimensions, `S3_VECTORS`. The index contains two vector entries.
- Three questions validated waiting period, repair-cost/excess terms, and first
  notice of loss. Each generated answer was supported by retrieved document
  content and returned the relevant S3 source citation.
- No Marketplace subscription, account upgrade, second region, external model,
  or persistent inference resource was introduced.

## Cost, tests, and limitations

- Current estimated recurring baseline remains about USD 76.89/month before
  usage, dominated by RDS, DMS, and two Secrets Manager interface-endpoint ENIs.
- Incremental RAG validation is usage-based and negligible at this two-document,
  three-question scale. No new continuously billed RAG resource was added.
- Focused package tests: ML `16 passed`; RAG `8 passed`. Real AWS E2E evidence
  takes precedence over unrelated Windows pytest/uv process cleanup issues.
- V1 intentionally does not claim production reliability, security hardening,
  CI/CD, exhaustive regression/failure testing, QuickSight, or Streaming proof.
  Those items are deferred or externally constrained as stated above.

V1 review is complete. Do not begin V2 without Human authorization.
