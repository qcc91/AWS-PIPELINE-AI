# Infrastructure tests

`validate.ps1` and `validate.sh` are offline-only, assertion-equivalent gates
for TASK-INF-001 through TASK-INF-004. They intentionally avoid provider
installation and every AWS operation.

Both scripts check all `terraform/**/*.tf` resource declarations against an
explicit path/type allowlists. Bootstrap, networking, reusable KMS/S3, IAM,
Glue, Lake Formation, and monitoring each have their own allowlist; resources
in other paths fail. Both gates also check:

- all four foundation/bootstrap DEV/PROD roots for the Sydney provider contract;
- initialized-root validation when both Terraform and provider cache exist;
- backend region, encryption, native lockfile, actual KMS ARN placeholder,
  bootstrap state key, environment role, and DEV/PROD isolation;
- module bootstrap/foundation key outputs and PROD `create_resources=false`;
- KMS/S3 deletion protection, lifecycle/versioning ordering, public controls,
  default SSE-KMS, TLS deny, and explicit wrong algorithm/key denies;
- missing encryption headers remain allowed for bucket default encryption;
- at least one same-account IAM role, valid role paths, and wildcard rejection;
- canonical multiline HCL blocks, output descriptions, workspace prohibition,
  and credential/secret patterns (including `*.hcl.example`).
- TASK-INF-003 network isolation, subnet derivation, tags, reusable KMS policy,
  and reusable S3 naming/lifecycle/encryption semantics;
- TASK-INF-004 IAM trust/action/resource and conditioned PassRole boundaries,
  exact Glue databases, Lake Formation registration/metadata matrix/RAG zero
  grants, and the complete conditioned KMS/S3/Logs/CloudTrail/SNS audit chain.

The CodeBuild buildspec runs in a Linux Bash environment. Terraform, TFLint,
Checkov, and the TFLint plugin should be pre-baked in the build image; the build
does not run `terraform init` or `tflint --init`. Missing tools are explicitly
marked `NOT RUN`, not reported as passed. An installed tool that fails exits
the build with a non-zero status.

On the 2026-09-08 Sol escalation host, the PowerShell gate passed. Terraform,
provider-backed validate, TFLint, and Checkov were NOT RUN because the tools and
provider caches were unavailable. The Windows Bash/WSL shim returned
`E_ACCESSDENIED`, so Bash execution was NOT RUN; source parity was reviewed but
is not represented as executable evidence.
