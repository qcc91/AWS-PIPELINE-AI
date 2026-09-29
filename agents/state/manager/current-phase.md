# Manager Current Phase

## V6/V6B final closeout — Human accepted 2026-09-30

V6 SageMaker Managed ML Pipeline and V6B Offline Feature Store + Unified Studio
Managed MLflow are accepted. PR #10 merged into `main`; managed execution
`zr3k4aa3lzfz` succeeded 9/9 with 120/120 Feature Store readback and valid Gold
output. The Small MLflow server is Stopped/Inactive after an explicit cost
deviation of approximately 14h52m and USD 9.55 versus the approved four-hour
window. Current work is documentation synchronization, protected merge, final
minimal proof CD verification and one V6 annotated tag. No PROD ML or V7.

## V6B — Feature Store + Unified Studio MLflow — implementation complete 2026-09-29

V6 SageMaker managed Pipeline is accepted. The active package extends only the
DEV claim-risk workflow with an offline-only SageMaker Feature Group and a
Terraform-managed Small SageMaker Managed MLflow server connected to the
existing Unified Studio project. Branch: `codex/v6b-feature-store-mlflow`.
No PROD ML deployment, endpoint, notebook, online Feature Store, new domain,
new project, V7, merge, or release tag is authorized.

Durable control-plane resources are deployed. Feature Group
`insurance-dev-claim-risk-features` is Created, uses the existing KMS key, S3
control bucket and Glue table
`insurance_dev_control.claim_risk_features_offline`, and has no Online Store.
Unified Studio connection `insurance-dev-claim-risk-mlflow` has connection ID
`490c7mbswsmzhe`. Managed MLflow experiment `insurance-claim-risk` contains
successful idempotent evidence run `e5caa62c88374b0c87b988394ef5dfee` for
accepted Pipeline execution `g46dxu0f1ydw`.

Validation execution `zr3k4aa3lzfz` succeeded with all nine managed steps. It
submitted and read back all 120 records through the offline Feature Store before
XGBoost training, then completed evaluation, the quality gate, model registration,
batch transform and Gold publication. Gold validation passed with 120 rows, 120
unique claims and zero invalid probabilities. Test AUC was 0.622222. Small MLflow
is `Stopped/Inactive`. It was inadvertently active for about 14h52m instead of
the approved four-hour maximum; estimated compute is approximately USD 9.55 at
USD 0.642/hour. This cost deviation remains explicit. V6B-scoped Terraform reports
`No changes`; the full foundation plan retains unrelated repository-refactor
source/path drift and therefore was not applied. Local regression is 151/151 and
all seven Terraform roots validate. Implementation is ready for PR review; merge,
release tagging, PROD ML deployment and V7 remain unauthorized.

## Current authorized enhancement — 2026-09-26

SageMaker managed ML Pipeline apply is Human-approved. Scope is now migration
of the existing successful ML flow into an AWS/UI-visible DAG; current Gold
data-quality remediation is deferred by Human. At that checkpoint no PROD or
separate next-version work was authorized; the V6 authorization above now
supersedes that historical statement.
Pipeline `insurance-dev-claim-risk` is deployed. Execution `g46dxu0f1ydw` uses
the unchanged six prepared V1 input files from
`ml/runs/insurance-dev-claim-risk-v1-20260910-061552/input/` and succeeded on
2026-09-27. All eight executed steps succeeded. Gold validation: 120 rows,
120 unique claims, zero invalid probabilities; test AUC 0.622222.
The final retries fixed exact-group model registration permissions and added
legacy dataset lineage only to an encrypted runtime manifest copy. Upstream
training and prediction were reused. Focused ML/security tests: 50 passed.
Athena validation: `938f0be5-bf34-4a36-8bbf-25748d872746`.
The latest scoped apply was 0 add / 2 update / 0 destroy (prepare script and
Pipeline parameter). This proof is not validation of the current Gold snapshot.
The earlier three failed runs exposed runtime KMS grant permission, enforced
Athena output-prefix permission, and non-AUTO vehicle-null validation issues.
The first two were fixed within the approved role/resource scope; the third
is deferred rather than changing business data. No ML feature library change.

The older package descriptions below are historical, not the current scope.

## Authoritative release status

V1–V5 are accepted and released. V5 annotated tag `v5.0-production-ready`
points to `5e0b479fa47130930dd9d4c0b0ad1005244ff335`. Post-merge pipeline
`bbd0ff68-3348-4010-ae2c-afdd008a1740` succeeded after Human approved the
exact PROD binary plan; only minimal proof metadata changed (0/1/0, no replacement).
No additional release bookkeeping commit was made at tagging time.

The portfolio cleanup was accepted and merged into `main`. Current package:
structural-only repository reorganization on
`codex/repository-structure-refactor`. Runtime code is being classified into
`pipelines/`, `workloads/`, and `infrastructure/`; documentation into the
current `docs/` responsibilities; Agent governance into `agents/`. Only moves
and path-reference corrections are authorized. No AWS calls or changes,
behavior changes, tag movement, release, or next version are authorized.
Stop before merge at REPOSITORY STRUCTURE REFACTOR HUMAN REVIEW CHECKPOINT.

## Historical implementation checkpoints

- Phase: V5 — Production readiness / operational hardening; IMPLEMENTATION COMPLETE, awaiting Human acceptance.
- Authorization: V5 monitoring, controlled DEV failure/recovery/replay, reconciliation, security regression and runbooks are approved. Full PROD platform expansion remains out of scope; V5 release tagging requires Human acceptance.
- V4 acceptance: source `f0a2d59858810dd30a186a47db0e1bc520672b0b`; pipeline `ed6d522f-4e09-4f7b-970e-354db652b48f` succeeded through DEV and Human-approved exact PROD plan apply, with final zero drift. Earlier V4 preparation entries below are historical.
- V5 local preparation: monitoring Terraform and Batch/CDC drill toolkit prepared; DEV bootstrap/foundation validate passed. AI regression 44 passed; Manager focused infrastructure/security/CD checks 21 passed and data reliability/drill checks 16 passed.
- V5 runtime status: monitoring and alert routing are deployed; Batch failure, quarantine, corrected recovery and duplicate replay passed. CDC retained-history replay exposed and fixed a Silver type-normalization defect, then succeeded with 10/10 DQ rules. Final Batch is 121/121 unique with zero negative rows; CDC is 3/3 unique with update/delete semantics preserved.
- V5 controls: all four alarms are OK; Batch and CDC controlled failures both reached ALARM and successfully invoked the existing SNS topic. Security ALLOW/DENY regression passed, integrated tests are 115/115, and bootstrap plus non-root foundation plans both report `No changes`.
- V1 baseline: accepted tag `v1.0-happy-path` remains at `9d4f625`.
- Active structured ingestion: Batch/File and PostgreSQL full-load+CDC feed one shared Bronze/Silver/Gold Iceberg Lakehouse.
- Streaming: RETIRED by Human decision. Code, Terraform, tests, AWS orchestration, docs, and active task state are removed; no replacement is allowed.
- Terraform V2 apply: complete, `8 added / 12 changed / 14 destroyed`; the 14 destroys were Streaming-only. Post-apply plan reports no changes.
- Processing boundary: separate Bronze, Silver, and Gold Glue jobs and Step Functions task/retry/failure boundaries for Batch and CDC.
- Batch evidence: normal 120-row run passed; same-content/different-key replay returned `DUPLICATE` in all stages; a 121-row DQ run quarantined one negative amount and published 120; controlled failure and recovery passed.
- RAG evidence: 2/2 local documents validated by stable SHA-256 identity; ingestion `JPIWFL7ZWT` scanned 2 with 0 failures and 0 changes; the unchanged repeat recorded `UNCHANGED_SKIPPED`; three grounded answers returned S3 citations.
- CDC evidence: two full-history replays passed; Athena confirmed three unique claims, INSERT/UPDATE semantics and the deleted payment absent.
- ML evidence: two identical postprocessing runs passed; Athena confirmed 120 unique predictions with complete run/model/dataset lineage.
- Glue DQ amendment: inline DQDL gates existing Silver jobs after row quarantine and before trusted writes. Real FAIL `dqresult-9459d89040c80af3581e3ee410fec754a9f7e8e7` scored 0.75 and left Silver/Gold unchanged; real PASS `dqresult-aa2e19613ead964a3c870ccc4b194b7fc4c88e8e` scored 1.0 and completed Gold.
- V2 release: accepted tag `v2.0-reliable` at `40855ff589314231c257a0b4441929178eea3b0b`.
- V3 preparation: security inventory, PII classification, conditional IAM/Lake Formation/KMS/CloudTrail Terraform and access-test design complete; local focused suite `87 passed`; Terraform fmt/validate passed.
- Real DEV baseline plan with V3 disabled: `0 add / 1 in-place change / 0 destroy`; only CloudTrail log-file validation would change, and it was not applied. An identity-enabled V3 plan was not fabricated.
- Identity bootstrap: Option A applied exactly `7 add / 0 change / 0 destroy`; one console-only IAM user, Operator and TerraformExecution roles now exist with no access key, login profile, or AdministratorAccess. MFA-context simulation passed, while no-MFA was denied.
- V3 result: MFA role chain, least privilege, Lake Formation persona grants, PII restrictions, KMS/S3/Secrets/CloudTrail hardening and real ALLOW/DENY tests passed. Foundation plan is zero drift and the integrated suite is 89 passed. See `docs/releases/v3/v3-completion-review.md`.
- V3 release: accepted implementation preserved by annotated tag `v3.0-governed` at `7993a73300c7d1330664bf812f5e2806c148c13e`.
- V4B design: protected `main` -> CodeConnections -> CodePipeline -> three isolated CodeBuild/proof-role boundaries. DEV auto plan/apply/validate; PROD read-only plan -> Human Approval -> exact binary plan apply.
- V4B local evidence: seven Terraform roots validate; focused V4B static suite and full repository suite pass (`97 passed`); repository consistency and high-confidence credential scanning pass.
- V4B AWS status: the bootstrap-managed narrow state/IAM handoff and all 31 isolated control-plane resources are applied with no deletion/replacement. `insurance-dev-v4b-cd` and its three CodeBuild projects exist; connection `06d021e7-aa2e-4dac-8307-cf2451a277bc` is `PENDING` one-time GitHub App authorization. DEV/PROD proof resources remain unapplied.
- Next: complete protected PR CI bookkeeping and STOP at the V5 Human acceptance checkpoint. Do not tag or begin another version before acceptance.

Last updated: 2026-09-29.
