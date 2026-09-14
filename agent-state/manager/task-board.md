# Manager Work-Package Board

| Package | Owner | Scope | Status |
|---|---|---|---|
| V1 Happy Path | Manager + Workers | DEV Batch, CDC, Athena BI, ML and RAG happy paths | ACCEPTED; tag `v1.0-happy-path` at `9d4f625` |
| V2 Streaming Retirement | Infrastructure + Data Workers | Remove Kinesis/Firehose-only code, Terraform, AWS orchestration, tests and docs | IMPLEMENTED; 14 Terraform-managed Streaming-only resources removed, no replacement |
| V2 Batch Reliability | Data + Infrastructure Workers | Stage boundaries, content idempotency, DQ, quarantine, audit, reconciliation | COMPLETE; normal, duplicate, negative-DQ, failure and recovery proofs passed |
| V2 CDC Reliability | Data + Infrastructure Workers | Stage boundaries, stable change identity, replay-safe current state, audit/reconciliation | COMPLETE; two replays and Athena I/U/D current-state proof passed |
| V2 ML Reliability | AI Worker | dataset validation/version, structured job audit, idempotent prediction publication | COMPLETE; two postprocessing runs and 120/120 Athena proof passed |
| V2 RAG Reliability | AI Worker | document identity/version, validation, overlap/throttling bounds, sync reconciliation | COMPLETE; real AWS sync/unchanged/retrieval proof passed |
| V2 Final Integration | Manager | consolidated review, tests, Terraform drift, docs, Git push | ACCEPTED; tag `v2.0-reliable` |
| V2 Glue Data Quality Amendment | Data + Infrastructure Workers, Manager review | Inline DQDL after row quarantine and before Silver write; real PASS/FAIL evidence | ACCEPTED; included in `v2.0-reliable` |
| V3 Security Inventory and Design | Manager + Infrastructure/Data/AI Workers | Inventory, PII classification, persona/LF/KMS/S3/Secrets/CloudTrail design | PREPARED; 87 tests pass; no AWS changes |
| V3 Identity Bootstrap | Human + Manager | Establish real non-root temporary-session entry for Operator | COMPLETE; MFA chain and bootstrap separation verified |
| V3 Apply and Access Proof | Manager + Workers | Non-destructive Terraform apply, ALLOW/DENY tests, V2 regression, zero drift | ACCEPTED; tag `v3.0-governed` at `7993a73` |
| V4A Pull Request CI | Infrastructure Worker + Manager | Full-repository GitHub Actions CI and protected-main enforcement | ACCEPTED; squash baseline `7ef6eab` |
| V4B Minimal-cost CD Proof | Infrastructure Worker + Manager | Isolated CodePipeline/CodeBuild control plane, DEV auto proof and approved exact PROD proof plan | IN PROGRESS; 31-resource control plane deployed without delete/replace; GitHub connection authorization, protected PR and real pipeline proof remain |

V5, full PROD platform deployment, comprehensive observability, paid security
services, QuickSight subscription, and any replacement streaming architecture
are out of scope. V4B may touch only its explicitly isolated PROD proof resource
after the required Human Manual Approval.
