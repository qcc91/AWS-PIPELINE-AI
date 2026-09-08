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
- 2026-09-08: The scoped TASK-INF-003 Sol correction was accepted after independent Manager review. The review confirmed path-specific resource allowlists, canonical multiline HCL, derived non-overlapping subnet contracts, no internet/NAT/interface resources, same-account path-capable KMS roles, explicit direct-role KMS actions, and private versioned SSE-KMS S3 controls.

## Current blockers

- None for TASK-INF-001 offline implementation.
- AWS account ID, execution role, CIDR conflict information, state retention, alert destination, and budget are required before applicable plan/apply checkpoints, not for TASK-INF-001.

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
