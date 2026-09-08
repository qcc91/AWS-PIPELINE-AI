# Infrastructure tests

`validate.ps1` is an offline-only boundary and secret scan for TASK-INF-001.
It intentionally avoids provider installation and all AWS operations.

The CodeBuild buildspec runs in a Linux Bash environment. Terraform, TFLint,
Checkov, and the TFLint plugin should be pre-baked in the build image; the
build does not run `terraform init` or `tflint --init`. Missing tools are
explicitly marked `NOT RUN`, not reported as passed. An installed tool that
fails exits the build with a non-zero status.
