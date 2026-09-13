# Data Engineering Worker Status

## V3 completion (2026-09-13)

- Lakehouse/control locations and persona grants are deployed.
- Analyst approved Gold ALLOW and Silver DENY passed; MLEngineer approved Gold
  ALLOW and Silver DENY passed. Secrets access was denied to both.
- `policy_performance` is excluded from whole-table Analyst access because
  `policy_id` is re-identifiable. RAGApplication has zero structured grants.
- Latest Batch and CDC orchestrations are SUCCEEDED. The DMS task's current
  failed state dates to 2026-09-11, before V3; full load was 5/5 with 0 errors.

- Current package: V3 data governance and PII classification support — DOCUMENTATION COMPLETE; AWS implementation not performed by this worker.
- V2 Batch/File, PostgreSQL CDC reliability, and accepted Glue Data Quality amendment remain complete.
- Actual implemented Iceberg tables were classified by field as PII YES/NO and HIGH/MEDIUM/LOW; unimplemented design entities were excluded from the V3 deployment claim.
- Proposed least-privilege consumers: Analyst receives Gold aggregate/reference tables plus explicit non-direct-PII column lists; MLEngineer receives only Gold `claim_risk_features` and `claim_risk`; RAGApplication receives no structured Lakehouse grant.
- Lake Formation read-only discovery completed on 2026-09-12 in account `199476069493`, `ap-southeast-2`: Glue has 4 DEV databases and 13 Bronze / 13 Silver / 16 Gold tables. LF has zero registered locations, default `IAM_ALLOWED_PRINCIPALS=ALL`, and one existing SageMaker execution role as data lake admin. The first permissions page shows explicit root plus `IAM_ALLOWED_PRINCIPALS` rights on Silver and no persona grants; it returned `NextToken`, and full pagination remains to be captured because the CLI login disappeared again on the immediate follow-up.
- The live result confirms governance is not yet enforced; no successful V3 governance result is claimed. Per-role positive/negative Athena validation commands remain documented in `docs/v3-data-governance.md` for post-implementation proof.
- V3 access-test design review found an apply blocker: `policy_performance` is currently in the Analyst whole-table LF grant but contains MEDIUM/PII YES `policy_id`. Remove it from the Analyst table list or implement an explicit column inclusion grant before claiming PII isolation.
- The accepted hybrid migration must prove Analyst/MLEngineer opt-ins are LF-enforced while legacy V2 pipeline roles remain functional; registered locations, TerraformExecution admin, old root Silver rights, IAM_ALLOWED_PRINCIPALS defaults, persona grants, and opt-ins all require captured post-apply evidence.
- The Worker execution context has no AWS profile or environment credentials. One instructed STS retry after a short wait returned `NoCredentials`; actual `aip-dev-human -> Operator -> persona` ALLOW/DENY tests remain pending in the authenticated Manager context. No AWS mutation was attempted.
- One shared Medallion Lakehouse remains; Batch and CDC are source mechanics, not separate data platforms.
- Batch: SHA-256 content identity, processed-file ledger, run/stage audit, row DQ, quarantine, within-file deduplication, reconciliation and idempotent Gold refresh.
- Real Batch baseline: 120 input, 120 output, 0 rejected, 0 duplicate in each stage.
- Real duplicate replay: same bytes under a different key produced `DUPLICATE`, input 120, output 0, duplicate 120 in Bronze/Silver/Gold.
- CDC: stable `_source_change_id`, I/U/D handling, source-order latest-state resolution, delete tombstones, run/stage audit and change-log-to-current-state reconciliation.
- Integrated Data/ML/RAG/Infrastructure suite: 82 passed.
- Streaming-specific source/runtime/tests are removed by Human decision; no replacement is planned.
- Real DQ proof: 121 input, 120 valid output, one negative amount quarantined, reconciliation passed and invalid claim absent from Gold.
- Real CDC proof: two identical 14-change replays produced the same current state; Athena confirmed three unique claims, the expected insert/update, and deleted payment absence.
- Controlled missing-object failure wrote stage/orchestrator audit; supplying the object produced a successful duplicate-safe recovery.

Last updated: 2026-09-12.
