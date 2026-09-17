# PROD state bootstrap design

TASK-INF-002 provides a separate PROD bucket name, KMS alias, backend role
placeholder, backend file, and bootstrap/foundation state-key contract.
`create_resources=false` is explicit, so the expected PROD resource count is
zero.

Future PROD inputs must use an approved same-account PROD role distinct from
DEV and an independently approved retention value. The backend KMS placeholder
must eventually be replaced by the actual PROD key ARN, never a DEV key or KMS
alias.

PROD remains design-only and undeployed. No plan or apply evidence is claimed.
