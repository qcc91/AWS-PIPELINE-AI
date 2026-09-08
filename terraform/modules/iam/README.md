# IAM foundation module

Creates a Terraform execution role and a Lake Formation data-location role,
each with one inline least-privilege policy. Terraform trust accepts only
explicit same-account role ARNs with paths. Lake Formation trust accepts only
`lakeformation.amazonaws.com`.

The registration role can list exactly two passed bucket ARNs, access only
objects below those buckets, and use only the passed Sydney KMS keys. Terraform
may pass only that registration role and only to Lake Formation. There is no
unconditional `iam:PassRole`, wildcard action, managed Administrator/PowerUser
policy, or account-root trust.

`Resource="*"` is confined to `ec2:DescribeAvailabilityZones` and
`sts:GetCallerIdentity`; these discovery APIs do not support resource-level
permissions. All S3, KMS, and PassRole permissions use
explicit input or created-resource ARNs. This Phase 1 policy supports safe
identity/discovery and review; any later deployment write boundary must be
reviewed as part of the exact P1-CP1 plan.
