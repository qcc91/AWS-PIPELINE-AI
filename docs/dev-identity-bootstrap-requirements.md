# DEV identity roadmap

## V1 override

The Human Owner has approved temporary use of the existing authenticated AWS
root CLI session for V1 planning and DEV deployment. This avoids blocking the
happy path on IAM Identity Center and named persona roles. It does not authorize
credential persistence, access-key creation, secret output, PROD deployment, or
any apply before reviewed-plan approval.

Proper non-root least-privilege execution and DataEngineer, Analyst,
MLEngineer, RAGApplication, KMS and Lake Formation role separation remain
required in V3.

## Final security boundary

No credentials or session tokens belong in this repository. Outside the
explicit V1 shortcut, the root principal must not be used as Terraform
execution identity, operator, KMS administrator, Lake Formation administrator,
or a data/application persona.

## V1 execution state

The approved host execution context has verified region `ap-southeast-2`,
account `199476069493`, and the exact same-account root caller. The V1 Terraform
roots use an explicit `allow_root_for_v1` switch. DEV enables it; PROD locks it
off. KMS policies scope root access to named management/data actions and do not
use `kms:*`.

V1 defers the Terraform execution role and Lake Formation persona/grant wiring
to V3, so no fabricated role ARN is needed for the happy-path plan.

## V3 migration requirement

Replace the shortcut with an MFA-protected, short-lived IAM Identity Center or
federated operator and distinct Terraform, KMS admin, Lake Formation admin,
DataEngineer, Analyst, MLEngineer and RAGApplication roles. Disable
`allow_root_for_v1`, update key policies, enable the retained IAM/Lake Formation
modules, run negative access tests, and verify root is absent from operational
use.

Plan/state artifacts remain ignored by Git and are retained for 90 days outside
the repository. A plan does not authorize an apply.
