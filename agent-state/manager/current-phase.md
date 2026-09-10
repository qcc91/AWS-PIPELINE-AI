# Manager Current Phase

- Phase: V1 — End-to-End Happy Path / Account Blocker Resolution.
- Status: Foundation, Batch, CDC, file-source expansion, Athena, and V1 ML
  complete; Streaming and RAG await external account actions.
- Default AWS Region: `ap-southeast-2`.
- Active environment: DEV. PROD remains design-only and prohibited.
- Account: `199476069493`, Human-approved temporary V1 root execution, current
  plan `FREE`; no credentials are persisted.
- Account constraint: remain on `FREE`; upgrading to `PAID` is prohibited.
- Streaming blocker: Kinesis `ListStreams` and Firehose
  `ListDeliveryStreams` return `SubscriptionRequiredException`. AWS provides no
  FREE activation mechanism; status is `ACCOUNT_PLAN_BLOCKED`.
- ML: COMPLETE. Effective quotas are Training 15 and Transform 8. One
  `ml.m5.large` Training and one Transform job completed; Gold `claim_risk`
  contains 120 predictions. Validation AUC is 0.65556 and Test AUC is 0.62222.
- RAG blocker: Knowledge Base and S3 Vectors are deployed; Titan Text
  Embeddings V2 is available/authorized, but on-demand RPM quota
  `L-26C560CE=0` is non-adjustable. Other Sydney candidates are zero-quota or
  violate Marketplace/cross-region/multimodal constraints. Basic Support review
  is the only remaining FREE-plan action.
- RAG Support submission: Basic Support case `178899964200695` was submitted by
  the Human Owner on 2026-09-10 and initially shows `Unassigned`. No Support-plan
  upgrade occurred; wait for AWS before any Titan retry.
- Latest Terraform refresh plan: 4 create/0 change/0 destroy, all Streaming.
- Tests: Terraform DEV validation, infrastructure static gate, secret checks,
  and 16 ML tests pass. Full-suite count is refreshed at package close.
- Fixed-cost estimate: about USD 76.89/month before usage. RDS, DMS, and the
  two-AZ Secrets Manager endpoint continue charging while idle.
- QuickSight remains intentionally deferred and unsubscribed.
- V2–V5 are not authorized.
- File-source expansion: COMPLETE. Seven reference/master CSVs plus 120 broker
  claims produced matching Bronze/Silver counts, seven Gold dimensions,
  `fact_claim_enriched`, `policy_performance`, `broker_performance`, and
  `claim_risk_features`; all 120 joins and as-of checks passed.
- Next action: monitor Bedrock Support case `178899964200695`. Streaming remains
  intentionally blocked under the FREE constraint. Do not begin V2.
- Last updated: 2026-09-10.
