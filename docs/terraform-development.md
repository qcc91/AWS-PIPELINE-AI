# Terraform development (TASK-INF-001)

Terraform roots are deliberately separated at `terraform/environments/dev` and
`terraform/environments/prod`. Terraform workspaces are not used for
environment or state isolation. Both providers explicitly pin
`ap-southeast-2`; credentials are supplied only by a future approved execution
role and never by configuration files.

The `terraform/modules/common` module defines the shared tag contract and
validates environment and data-classification inputs. It creates no resources.
Bootstrap roots are placeholders for TASK-INF-002.

Run the offline gate with:

```powershell
./tests/infrastructure/validate.ps1
```

The gate runs `terraform fmt -check` when Terraform is installed, validates
initialized roots without downloading providers, and always performs static
resource, workspace, region, and credential checks. `tflint` and `checkov` are
optional local tools; missing tools are recorded rather than installed. The
buildspec is validation-only and must not be changed to run `terraform init`,
`plan`, or `apply` in this phase.

The baseline is Terraform 1.16.1 (constraint `>=1.16.0,<1.17.0`), AWS provider
6.x, and TFLint AWS ruleset 0.48.0. Upgrades require an explicit review and
regression of both roots and all modules. The CI entrypoint uses Bash for the
default Linux CodeBuild image; `validate.ps1` is the equivalent local Windows
entrypoint. TFLint is invoked recursively and fails if installed but not
initialized, rather than silently treating that as a pass.
