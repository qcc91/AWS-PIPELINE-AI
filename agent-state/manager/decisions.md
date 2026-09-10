# Manager Decisions and Approvals

## Human approvals

- 2026-09-08: Gate 1 approved.
- 2026-09-08: Phase 1 execution plan approved.
- TASK-INF-001 through TASK-INF-005 may be delegated and implemented.
- No AWS resource-changing operation is authorized.

## Approved assumptions

- Primary region: `ap-southeast-2` (Sydney).
- No silent second region; unavailable required capability triggers `ARCHITECTURE_DECISION_REQUIRED`.
- DEV is the primary deployed environment.
- PROD has separate Terraform environment/state design and remains undeployed until explicit approval.
- Batch analytics RPO: 24 hours (project assumption).
- Analytical pipeline RTO: 4 hours (project assumption).
- Streaming: best-effort near-real-time and not life-critical.
- PII roles: DataEngineer, Analyst, MLEngineer, RAGApplication as defined in architecture/data-contracts.md.

## Architecture decisions

- Bronze, Silver, and Gold all use Apache Iceberg.
- Terraform backend design uses S3 native lockfile; no DynamoDB locking.
- No NAT Gateway in Phase 1.
- TASK-INF-006 is held until P1-CP1 explicit Human approval.

## Model routing

- Manager remains the parent orchestration agent.
- Worker implementation defaults to GPT-5.6 Luna when explicit routing is available.
- 2026-09-08: TASK-INF-002 escalated from GPT-5.6 Luna to GPT-5.6 Sol after two focused correction attempts. Reason: HCL remained non-canonical and potentially unparsable due to multiple arguments compressed into single-line blocks; Bash gate still lacked parity for secret and security assertions. Escalation is limited to completing TASK-INF-002.
- 2026-09-08: TASK-INF-003 escalated from GPT-5.6 Luna to GPT-5.6 Sol after two focused correction attempts. Reason: new modules still contained extensive single-line HCL; the PowerShell gate used a cross-module union allowlist; the Bash gate did not admit or validate TASK-INF-003; IAM role-path and data-classification validations remained incomplete. Escalation is limited to completing TASK-INF-003.
- 2026-09-08: TASK-INF-004 escalated from GPT-5.6 Luna to GPT-5.6 Sol after two focused correction attempts. Reason: both corrections returned incomplete; the second still failed the offline gate and omitted the CloudTrail audit/KMS/delivery security chain, Lake Formation role matrix, canonical HCL, and Bash parity. Escalation is limited to completing TASK-INF-004.
- 2026-09-08: The scoped TASK-INF-004 Sol correction returned with the reported gaps addressed and is awaiting independent Manager review; it is not accepted yet.
- 2026-09-08: The scoped TASK-INF-003 Sol correction was accepted after independent Manager review. The review confirmed path-specific resource allowlists, canonical multiline HCL, derived non-overlapping subnet contracts, no internet/NAT/interface resources, same-account path-capable KMS roles, explicit direct-role KMS actions, and private versioned SSE-KMS S3 controls.

## Current blockers

- A fresh AWS CLI login in the Terraform execution context is required to refresh the deployed state and produce a trustworthy unified V1 plan.
- CDC recurring compute alone is estimated at about USD 59.13/month before storage and PrivateLink, above the approved USD 12/month review threshold. Apply therefore requires an explicit Human cost decision at the Terraform Plan Approval gate.
- QuickSight is not subscribed. V1 BI can proceed with Athena while QuickSight remains disabled; enabling QuickSight requires a separate edition/subscription cost decision.

## Manager reviews

- TASK-INF-001 accepted on 2026-09-08 after two focused Luna corrections.
- Corrections addressed current tool/provider baselines, valid Terraform `-chdir` usage, Linux CodeBuild compatibility, recursive lint coverage, broader secret scanning, per-environment region checks, and YAML-safe buildspec commands.
- Local offline PowerShell gate passed. Terraform, TFLint, Checkov, Bash, and YAML parser execution remain NOT RUN/unavailable and must not be represented as passing evidence.
- AWS changes for TASK-INF-001: None.
- TASK-INF-002 accepted on 2026-09-08 after two Luna corrections and one scoped Sol escalation.
- Manager static review confirmed 9 expected DEV bootstrap resource instances, zero PROD instances, S3/KMS deletion protection, default and explicit-header encryption controls, same-account role-path validation, environment-separated backend examples, and equivalent PowerShell/Bash source assertions.
- Manager added root `.gitignore` as a small security integration fix to prevent Terraform state, populated backend config, tfvars, and plan artifacts from entering Git. Provider-backed Terraform validation remains NOT RUN and is carried as a P1-CP1 risk.
- AWS changes for TASK-INF-002: None.
- TASK-INF-003 accepted on 2026-09-08 after two Luna corrections and one scoped Sol escalation.
- Manager executed the PowerShell offline gate successfully. Terraform fmt/validate, TFLint, Checkov, and Bash remain NOT RUN/unavailable; provider-backed validation risk is carried to TASK-INF-005/P1-CP1.
- AWS changes for TASK-INF-003: None.
- TASK-INF-004 accepted on 2026-09-08 after two incomplete Luna corrections, one scoped Sol escalation, and a targeted Manager review correction.
- Manager review confirmed 32 module-level expected instances before environment integration: IAM 4, Glue 4, Lake Formation 10, and monitoring 14. RAGApplication is only a validated zero-grant boundary; no RAG or Bedrock resource exists.
- The targeted correction split CloudTrail KMS GenerateDataKey/DescribeKey conditions, added explicit current and noncurrent audit-log retention, removed database DROP from DataEngineer, and removed unnecessary ListAllMyBuckets access.
- The PowerShell TASK-INF-001/002/003/004 gate passed. Terraform/provider validation, TFLint, Checkov, and Bash remain NOT RUN and are carried to TASK-INF-005/P1-CP1.
- AWS changes for TASK-INF-004: None.
- 2026-09-08: TASK-INF-005 escalated from GPT-5.6 Luna to GPT-5.6 Sol after two focused correction attempts. Reason: both corrections returned before implementing DEV module wiring, PROD zero-resource gating, the approved resource manifest, plan JSON validation, or TASK-INF-005 topology assertions. Escalation is limited to completing TASK-INF-005 static integration; actual plan/apply remains prohibited or unavailable.
- 2026-09-08: Manager selected a separate Phase 1 `control` bucket and deferred `artifacts` storage until the ML phase. This resolves the Glue/Lake Formation control-location interface without exceeding the approved six-bucket foundation cap or changing the USD 4–12/month boundary.
- 2026-09-08: TASK-INF-005 static integration was accepted after independent Manager review. DEV defines 76 approved foundation instances; PROD is validation-locked to zero. The exact address manifest and PowerShell/Bash plan JSON validators are ready, but no plan JSON was fabricated and actual Terraform plan remains NOT RUN.
- 2026-09-08: Manager removed direct DataEngineer/Analyst/MLEngineer grants from the shared platform KMS key. Phase 1 uses an empty direct user list; future workload roles must receive scoped IAM and Lake Formation authorization for approved datasets.
- 2026-09-08: DEV and PROD roots now declare partial S3 backends, and an explicit USD 12 monthly review threshold is captured as input only; no AWS Budgets resource is introduced.
- P1-CP1 is reached as a stop point, but AWS-change approval is not yet safely actionable because provider-backed validation and exact bootstrap/foundation plans are unavailable.
- 2026-09-08: Human accepted the P1-CP1 static review and authorized Plan Preparation only; `terraform apply` remains prohibited.
- Read-only discovery found no local Terraform, AWS CLI, TFLint, Checkov, AWS credential environment indicators, AWS config/credentials files, or AWS PowerShell modules. STS identity discovery and real plan generation were therefore NOT RUN.
- 2026-09-09: Human approved the simplified package execution model. Sol Manager retains architecture, package scoping, integration, and final review; Luna Workers implement and test complete packages. Routine formatting, validation, provider, syntax, lint, test, and rework failures no longer create Human checkpoints.
- 2026-09-09: TASK-INF-001–005 are consolidated as `PHASE-1-INFRASTRUCTURE-PACKAGE`. The only next Human stop is a trustworthy Terraform Plan Approval, unless a material architecture, security, cost, or required identity decision blocks progress.
- 2026-09-09: Terraform 1.16.1 and AWS CLI 2.36.40 were located. DEV bootstrap and foundation both completed `init -backend=false` with signed HashiCorp AWS provider 6.63.0 and passed real `terraform validate`; recursive `fmt -check` passed. TFLint and Checkov remain unavailable.
- 2026-09-09: The Codex process has no AWS profile, credentials, or configured region. The Human-reported root session was not used. Root is prohibited as Terraform execution/operator/KMS/Lake Formation/data-role identity. Account, VPC, and IAM discovery and real plan remain NOT RUN until a dedicated non-root short-lived session is available.
- 2026-09-09: Human replaced the phase-first delivery strategy with one cumulative V1–V5 roadmap. Final architecture and requirements remain unchanged; only V1 end-to-end happy path is currently authorized. Existing correct V2–V5 hardening is retained but will not be perfected unless it blocks V1.
- 2026-09-09: Existing repository work maps mainly to the V1 infrastructure foundation. No executable batch, CDC, streaming, Iceberg transformation, BI, ML, or RAG implementation exists yet. The next package remains V1 infrastructure plan preparation, followed by the practical V1 packages documented in `docs/v1-implementation-plan.md`.
- 2026-09-09: Human approved a V1-only identity policy override. Temporary root execution is a Human-approved V1 shortcut for Terraform planning and DEV deployment; credentials must never be printed, persisted, or turned into access keys. Proper least-privilege IAM and role separation remain required in V3.
- 2026-09-09: With approved host execution permission, AWS CLI in the same context intended for Terraform confirmed `ap-southeast-2`, account `199476069493`, and the account root ARN. Read-only discovery found one default VPC `172.31.0.0/16`, which does not overlap proposed `10.20.0.0/16`, and three available Sydney AZs including the proposed `2a` and `2b`.
- 2026-09-09: Read-only discovery found no existing non-shadow CloudTrail trail and no matching project S3 bucket, KMS alias, or Glue database. DEV V1 plans were generated without apply: bootstrap 9 create/0 change/0 destroy; foundation 62 create/0 change/0 destroy. The foundation JSON passed the exact approved-address manifest check.
- 2026-09-09: Active DEV roots use local state for V1 plan/bootstrap ordering; reviewed S3 backend templates remain the V4 migration target. Plan/state artifacts are Git-ignored. This does not authorize apply.
- 2026-09-09: Human approved V1 DEV bootstrap/foundation apply. Final deployed state contains exactly 9 bootstrap and 62 foundation resources; both post-apply refresh plans report no changes. No PROD resource was created.
- 2026-09-09: Initial bootstrap apply exposed two missing KMS permissions caused by the deliberately enumerated V1 root policy: Terraform required key-policy/rotation/tag reads and alias lifecycle actions. Manager added only explicit management/read/tag/alias actions, never `kms:*`, recovered the existing key through in-place policy updates, and created no duplicate or orphan key. Foundation then applied exactly 62/0/0.
- 2026-09-09: After infrastructure verification, work proceeds to V1-BATCH-LAKEHOUSE implementation and plan preparation. Any new AWS resource apply still requires review of that package's Terraform plan; V2–V5 remain unauthorized.
- 2026-09-09: Manager accepted V1-BATCH-LAKEHOUSE implementation after one Worker correction pass. The accepted design uses one Glue 5.0 Spark job and Standard Step Functions workflow, reuses foundation storage/KMS/catalog, and writes Bronze, Silver, and Gold as Iceberg. AWS's optimized Glue `.sync` integration requires four Glue actions on `Resource="*"`; this documented service limitation is isolated to the state-machine execution role.
- 2026-09-09: The real V1-BATCH-LAKEHOUSE plan contains 14 creates, zero changes, and zero destroys, all under `module.batch_ingestion`. It does not alter the 71 deployed bootstrap/foundation resources. Apply remains gated by Human plan approval.
- 2026-09-09: Human approved the reviewed V1 Batch plan and accelerated real Batch execution. Terraform applied exactly 14 creates, zero changes, and zero destroys. No additional service or destructive operation was required.
- 2026-09-09: V1 Batch Happy Path is COMPLETE. EventBridge started Step Functions execution `2d7cdc10-e77b-ca90-16fb-515c38629245_9b70b01d-6953-28c8-edc7-1b7645fcf452`; Glue run `jr_b811c71548f596a7b60b3125ec8e20e36bcfa19e2adcbb5c2c1384a9c0a815ba` succeeded in 82 seconds. Athena verified 3 Bronze rows, 3 Silver rows, 3 Gold facts, total claim amount 5290.50, and the expected three daily status summaries.
- 2026-09-09: Post-apply Terraform refresh reports zero drift. State contains 9 bootstrap resources and 76 foundation/batch resources. The next authorized work is V1 CDC implementation and plan preparation; CDC apply remains subject to Terraform plan review.
- 2026-09-09: Human directed parallel V1 execution. Manager launched BI, ML, and RAG Workers concurrently once the Batch Gold contract stabilized, then launched Streaming when a Worker slot became available. All five remaining V1 packages are integrated into the cumulative DEV root for a unified plan; none has been applied.
- 2026-09-09: Manager read-only discovery confirmed PostgreSQL 16.15 on `db.t4g.micro`, DMS 3.6.1 on minimum available `dms.t3.small`, the existing `dms-vpc-role` and `dms-cloudwatch-logs-role`, Secrets Manager PrivateLink, Titan Text Embeddings V2, Nova Micro, and S3 Vectors in Sydney. QuickSight is not subscribed in account `199476069493`.
- 2026-09-09: CDC Manager corrections add a two-AZ Secrets Manager endpoint, DMS-compatible secret, delete-event preservation, Glue self-referencing security group and ENI permissions, and AWS-resource-scoped KMS grant creation. The generated password is sensitive local Terraform state plus Secrets Manager only; V3/V4 must remove this local-state security shortcut.
- 2026-09-09: Official Price List discovery found recurring CDC compute alone at roughly USD 59.13/month (RDS 18.25 plus DMS 40.88 for 730 hours), before storage and PrivateLink. This is a material cost increase above the USD 12/month threshold and requires Human approval; no apply is authorized.
- 2026-09-09: Consolidated Manager review accepted the local CDC, Streaming, BI, ML, and RAG implementations for real plan preparation. `terraform fmt -check`, DEV `terraform validate`, 31 Python tests, Python compilation, the infrastructure static gate, `git diff --check`, and the repository secret scan pass. This acceptance authorizes planning only, not apply.
- 2026-09-09: The real unified DEV plan succeeded after one routine DMS provider enum correction. Exact actions are 78 creates, one in-place platform KMS key-policy change, and zero destroys; 75 existing resources are no-op. Creates split as CDC 39, Streaming 18, ML 10, RAG 8, and BI 3. The KMS change adds only `kms:CreateGrant` with `kms:GrantIsForAWSResource=true`. No Lake Formation change is planned.
- 2026-09-09: The estimated new always-on baseline is USD 90.32/month: RDS compute 18.25, RDS gp3 storage 2.76, DMS compute 40.88, two endpoint ENIs 14.60, one Kinesis shard 13.43, and one secret 0.40, before usage-based charges. This requires explicit Human cost approval; no apply has occurred.
- 2026-09-10: Human approved the V1 package-level execution and recurring CDC cost. CDC is COMPLETE: DMS full load reached 100% for five tables with zero errors; EventBridge, Step Functions, and Glue succeeded; Athena confirmed the expected insert/update/delete current state.
- 2026-09-10: The reliable V1 DMS configuration uses a new source endpoint with no explicit PostgreSQL `SlotName`, allowing DMS to manage its default slot. Changing the replication task caused a replacement of the earlier failed task (two creates/one destroy); the removed task had processed zero rows. The unused custom-slot endpoint remains to avoid another destructive change.
- 2026-09-10: Account capability preflight is now mandatory before apply. Streaming is isolated because Kinesis returns `SubscriptionRequiredException`; its four resources remain unapplied. ML is isolated because all discovered Sydney SageMaker training quotas are zero; no training job or training charge was created. RAG infrastructure is deployed, but ingestion is isolated after bounded attempts consistently returned Titan Embeddings HTTP 429.
- 2026-09-10: Athena BI is functional; QuickSight remains intentionally disabled because the account is not subscribed. The fixed-cost estimate is now about USD 76.89/month before usage because the USD 13.43 Kinesis shard was not created.
- 2026-09-10: Human-authorized DocuVera cleanup is COMPLETE. Deleted the DocuVera S3 bucket including 802 version/delete-marker entries, EventBridge rule, Step Functions state machine, eight Glue jobs, two Glue databases, DocuVera IAM roles/policies, DMS log group, and RDS parameter group. A post-delete scan found no remaining DocuVera-named resources in the reviewed services.
- 2026-09-10: `V1 ACCOUNT BLOCKER RESOLUTION PACKAGE` read-only diagnosis confirmed account plan `FREE` with USD 99.91 remaining credit. Kinesis `ListStreams` and Firehose `ListDeliveryStreams` both return `SubscriptionRequiredException`; AWS documents both as Paid Plan services. A Human billing-plan upgrade is required before Streaming can continue.
- 2026-09-10: SageMaker `ml.m5.large` account quotas in Sydney are zero for training (`L-611FA074`) and transform (`L-236AE59F`), both adjustable, with no request history. Minimum V1 values are one each; all discovered training-instance quotas are zero, so no instance substitution is approved.
- 2026-09-10: Titan Text Embeddings V2 is available, authorized, and entitled in Sydney, but its live on-demand RPM quota `L-26C560CE` is zero and non-adjustable (TPM `L-DE641971` is also zero). Bedrock Agent `StartIngestionJob` consequently fails validation around a nested BedrockRuntime HTTP 429. Human account/Support action is required; retries are suspended.
- 2026-09-10: Human prohibited upgrading the account from `FREE` to `PAID`. Streaming is therefore `ACCOUNT_PLAN_BLOCKED`; official AWS plan documentation exposes no quota, entitlement, IAM, Organizations, or advanced-feature activation path for Kinesis/Firehose under FREE. The ready architecture/code remains unchanged.
- 2026-09-10: Human authorized non-billable quota requests. SageMaker Training request `b519d760dde9440687b17fbd2080ff62OTPDTvP7` (case `178899797700557`) and Transform request `3b77277e7eba45ca8519f986852b485dtx2kZBLr` (case `178899780000820`) were submitted for value one and reached `CASE_OPENED`. No compute or billable resource was created.
- 2026-09-10: RAG alternative discovery found no usable FREE-compatible Sydney embedding model. Titan Text V2 and Multimodal effective RPM are zero; Cohere English/Multilingual effective RPM is zero with unavailable Marketplace agreement; Cohere v4 is an inference-profile/cross-region path. Retain Titan V2 and request a Basic Support quota/entitlement review without purchasing Support.
- 2026-09-10: Human authorized automatic Basic Support request submission when available. Read-only `support:DescribeServices` returned `SubscriptionRequiredException` because the Support API requires Premium Support. Automatic API submission is unavailable and no Support-plan purchase is authorized; the prepared Titan request requires Human submission in the Basic Support console.
