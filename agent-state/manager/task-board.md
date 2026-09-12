# Manager Work-Package Board

| Package | Owner | Scope | Status |
|---|---|---|---|
| V1 Happy Path | Manager + Workers | DEV Batch, CDC, Athena BI, ML and RAG happy paths | ACCEPTED; tag `v1.0-happy-path` at `9d4f625` |
| V2 Streaming Retirement | Infrastructure + Data Workers | Remove Kinesis/Firehose-only code, Terraform, AWS orchestration, tests and docs | IMPLEMENTED; 14 Terraform-managed Streaming-only resources removed, no replacement |
| V2 Batch Reliability | Data + Infrastructure Workers | Stage boundaries, content idempotency, DQ, quarantine, audit, reconciliation | COMPLETE; normal, duplicate, negative-DQ, failure and recovery proofs passed |
| V2 CDC Reliability | Data + Infrastructure Workers | Stage boundaries, stable change identity, replay-safe current state, audit/reconciliation | COMPLETE; two replays and Athena I/U/D current-state proof passed |
| V2 ML Reliability | AI Worker | dataset validation/version, structured job audit, idempotent prediction publication | COMPLETE; two postprocessing runs and 120/120 Athena proof passed |
| V2 RAG Reliability | AI Worker | document identity/version, validation, overlap/throttling bounds, sync reconciliation | COMPLETE; real AWS sync/unchanged/retrieval proof passed |
| V2 Final Integration | Manager | consolidated review, tests, Terraform drift, docs, Git push | COMPLETE; awaiting Human review |
| V2 Glue Data Quality Amendment | Data + Infrastructure Workers, Manager review | Inline DQDL after row quarantine and before Silver write; real PASS/FAIL evidence | COMPLETE; FAIL 0.75/PASS 1.0, 82 tests; awaiting Human acceptance |
| V3 Security Inventory and Design | Manager + Infrastructure/Data/AI Workers | Inventory, PII classification, persona/LF/KMS/S3/Secrets/CloudTrail design | PREPARED; 87 tests pass; no AWS changes |
| V3 Identity Bootstrap | Human + Manager | Establish real non-root temporary-session entry for Operator | TERRAFORM APPLIED; awaiting Human console password/MFA enrollment |
| V3 Apply and Access Proof | Manager + Workers | Non-destructive Terraform apply, ALLOW/DENY tests, V2 regression, zero drift | BLOCKED only on interactive enrollment |

V4–V5, PROD, CI/CD, comprehensive observability, paid security services,
QuickSight subscription, and any replacement streaming architecture are out of scope.
