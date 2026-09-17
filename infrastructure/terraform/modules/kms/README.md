# KMS module

Creates one customer-managed symmetric KMS key and one alias. Rotation is
enabled, the deletion window is 30 days, and `prevent_destroy` protects the
key.

At least one administrator role is required; the user-role list may be empty.
Both lists accept explicit same-account IAM role ARNs with normal role paths
and reject wildcard or cross-account principals. Direct administrators receive
an explicit set of key-management actions and never `kms:*`. Direct users
receive only `Encrypt`, `Decrypt`, `GenerateDataKey*`, `DescribeKey`, and
`ReEncrypt*` data-plane operations.

KMS administration uses explicit same-account non-root admin role ARNs and
never grants account-root delegation.

The complete project tag contract has no defaults. Required values must be
non-empty, the tag environment must match the module environment,
`ManagedBy` must be `terraform`, and `DataClassification` must be approved.
