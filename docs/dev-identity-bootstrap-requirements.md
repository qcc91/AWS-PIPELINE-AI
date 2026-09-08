# DEV non-root identity bootstrap requirements

## Security boundary

The AWS account root principal is discovery-only for the current preparation
stage and must not be used as Terraform execution identity, operator, KMS
administrator, Lake Formation administrator, DataEngineer, Analyst,
MLEngineer, or RAGApplication. No credentials or session tokens belong in this
repository.

## Minimum prerequisite before a trustworthy plan

Prefer an AWS IAM Identity Center human operator with MFA and short-lived CLI
credentials. The session must be non-root and must expose its role ARN through
`aws sts get-caller-identity`. If an existing non-root administrator/operator
identity already exists, it may be used temporarily for DEV bootstrap and plan
preparation after Human approval; no long-lived IAM access key is required.

The temporary DEV operator may also be nominated as KMS administrator for the
bootstrap key. For the foundation plan, the current Terraform validation
requires distinct Lake Formation administrator, registration, DataEngineer,
Analyst, MLEngineer, and RAGApplication role ARNs. These identities may not be
invented, replaced with root, or collapsed into one role.

If no suitable non-root operator exists, the Human Owner must use the AWS
account recovery/root path once, outside this project automation, to enable IAM
Identity Center or create a short-lived federated administrator path. Root
credentials must then be closed and not supplied to Codex. This is the minimum
account bootstrap needed before this project can safely discover or plan.

## Required read-only discovery

Using the approved non-root session in `ap-southeast-2`, verify:

- account ID and caller ARN;
- all existing VPC CIDRs and overlap with `10.20.0.0/16`;
- availability of two Sydney AZs;
- exact existing role ARNs for operator, KMS admin, Lake Formation admin,
  DataEngineer, Analyst, MLEngineer, and RAGApplication;
- whether the operator can assume the intended DEV Terraform role.

Only exact discovered or Human-provided ARNs may enter a non-committed tfvars
file. Plan/state artifacts remain ignored by Git and are retained for 90 days
outside the repository. A plan does not authorize an apply.
