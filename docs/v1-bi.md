# V1 BI package

The BI path exposes the DEV Gold Iceberg contract through an encrypted Athena
workgroup and two named queries: `fact_claim` and `claim_daily_summary`.
Both queries select only Gold business columns and contain no direct customer
PII. Athena results are written to the existing encrypted control bucket.

QuickSight dataset resources are deliberately opt-in (`enable_quicksight =
false`). Before enabling them, the Human Owner must provide:

1. The subscribed QuickSight account ID (and confirm the namespace).
2. The subscribed edition (`STANDARD` or `ENTERPRISE`).
3. An approved QuickSight user/group principal ARN.
4. Confirmation that the account's QuickSight service-linked permissions and
   Lake Formation/Athena access are available.

These are account-level inputs and cannot be inferred from the AWS account ID.
Consequently a complete QuickSight analysis/dashboard plan is blocked until
they are explicit. The repository includes the dataset definition and a
minimal dashboard design in `src/bi/dashboard-design.md` for that follow-up.

Manager read-only discovery on 2026-09-09 returned `ResourceNotFoundException`
for both account subscription and namespace `default`. This account is not
currently registered for QuickSight, so enabling the optional data source and
dataset requires a separate Human edition/cost decision and account-level
subscription before apply.

## Cost and security

Athena is pay-per-query and the V1 dataset is Direct Query; the small demo
workload should remain negligible. QuickSight has account/user subscription
charges and is therefore excluded by default. Athena result encryption uses
the existing platform KMS key. No new AWS service, public bucket, or
long-running compute is introduced.
