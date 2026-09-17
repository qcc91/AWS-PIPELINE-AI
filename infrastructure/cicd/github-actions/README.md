# GitHub Actions runtime location

GitHub requires active workflow definitions to remain under the repository-root
`.github/workflows/` directory. The active pull-request workflow is therefore:

`../../../.github/workflows/pull-request-ci.yml`

This directory records its logical ownership by `infrastructure/cicd` without
duplicating the workflow or changing GitHub Actions runtime behavior.
