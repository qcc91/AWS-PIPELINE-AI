# V4 GitHub Actions CI

The repository's pull-request gate is `.github/workflows/pull-request-ci.yml`.
It is intentionally AWS-independent: it has read-only repository permissions,
does not configure AWS credentials, and cannot run Terraform `plan` or `apply`.
AWS continuous delivery is deliberately deferred to the separately authorized
V4B package.

## Checks

Every pull request targeting `main` runs:

1. high-confidence credential and repository consistency checks;
2. `terraform fmt -check -recursive terraform`;
3. backend-free provider initialization and `terraform validate` for the DEV
   and PROD foundation/bootstrap roots; and
4. focused Python and static infrastructure/security tests in `tests/data`,
   `tests/infrastructure`, `tests/ml`, and `tests/rag`.

The workflow uses no AWS secrets. `requirements-ci.txt` contains only the
runtime packages needed by the offline-safe focused tests.

## Required main-branch rules

The GitHub repository owner should configure a branch ruleset for `main` with
these settings:

- require a pull request before merging;
- require the successful `Terraform, Python, and security checks` status check;
- dismiss stale approvals when the pull request changes;
- prevent force pushes and branch deletion; and
- restrict direct pushes to maintainers/break-glass administrators only.

The required status check name is the job name, not the workflow file name:
`Terraform, Python, and security checks`.

## Configuration evidence

The configured remote is `https://github.com/qcc91/AWS-PIPELINE-AI.git`.
The V4A acceptance evidence must record the real pull request numbers, one
intentional failing run, the corrected passing run, and the resulting merge
decision under the protected `main` ruleset. No GitHub or AWS credential is
stored in the repository.

Evidence captured on 2026-09-13:

- Pull request: `#1` (`codex/v4-cicd` -> `main`).
- Passing run: Actions run `34753016943`, job `103712621588`.
- Intentional failure: commit `542e6ce5e17b27886d2fdfa3bd962dbbae35ff1c`,
  Actions run `34753153099`, job `103712975546`.
- GitHub reported PR `mergeable_state=blocked` while that required check was
  failing.
- `main` protection requires a pull request and the exact check
  `Terraform, Python, and security checks`, applies to administrators, and
  disables force pushes and branch deletion.

The intentional failing test existed only for the negative proof and was
removed immediately afterward.

## Local invocation

From the repository root:

```text
python scripts/ci/check_repository_consistency.py
terraform fmt -check -recursive terraform
python -m pytest -q tests/data tests/infrastructure tests/ml tests/rag
```

The workflow's Terraform initialization uses `-backend=false`, so pull-request
CI never reads or writes remote state and never contacts AWS.
