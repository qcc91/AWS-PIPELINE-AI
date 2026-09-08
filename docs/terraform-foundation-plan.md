# Foundation integration plan

The final design keeps separate DEV and PROD S3 backend keys
(`foundation/terraform.tfstate`) and Sydney providers. For V1, DEV uses local
state so both bootstrap and foundation can be planned before the state bucket
exists. The reviewed S3 backend template is retained for V4 migration. PROD
has `enable_deployment=false`; no production resources are authorized.

Plan evidence was generated on 2026-09-09 from the same approved host execution
context used for AWS discovery. The read-only sequence was `terraform
init -backend=false`, `terraform plan -out=.terraform/dev-foundation.tfplan`,
and JSON inspection. Binary and JSON plans remain under ignored `.terraform/`
paths and are not committed. No apply is permitted before P1-CP1 Human
approval.

The real V1 DEV foundation plan contains exactly 62 creates, zero changes, and
zero destroys. The separate real bootstrap plan contains exactly 9 creates,
zero changes, and zero destroys. PROD remains zero actions by default.

The machine-readable contract is `tests/infrastructure/approved-plan-manifest.json`.
The generated foundation plan JSON passed `validate-plan.ps1`: it contains
exactly the 62 approved addresses with no update/delete/replace action. The
Bash parity script was not run because a usable Bash runtime is unavailable.
Plan JSON is sensitive and is not committed.

Phase 1 cost remains the approved USD 4–12/month planning range, including
three KMS keys, low-volume S3, CloudTrail/log requests, and SNS requests. Any
additional endpoint, compute, or retention cost requires re-estimation.

The three fixed KMS components are state bootstrap, platform data, and audit
encryption (approximately USD 1/month each before requests). V1 foundation has 62
instances, bootstrap has 9, and PROD has 0.

The 14-instance reduction from the prior foundation design defers the two IAM
roles/two policies and ten Lake Formation governance resources to V3. Their
reviewed modules remain in the repository; V1 does not require persona ARNs.

Rollback is a reviewed Terraform state operation: preserve versioned state,
reverse dependencies, and never bypass `prevent_destroy` without explicit
Human approval. Bootstrap state recovery uses prior S3 versions and lock
contention investigation.

Terraform 1.16.1 and the signed HashiCorp AWS provider 6.63.0 are initialized;
both DEV roots pass real `terraform validate` and recursive formatting checks.
Read-only AWS discovery confirmed account `199476069493`, region
`ap-southeast-2`, available AZs `2a`/`2b`, no project-name collisions, and no
overlap between the existing default VPC `172.31.0.0/16` and planned
`10.20.0.0/16`. No existing account trail was found. Temporary root execution
is a Human-approved V1 shortcut; least-privilege identity separation remains a
required V3 outcome.
