# Data Engineering Worker Status

## V5 data operations package

Status: local implementation complete; real AWS drill pending Manager
integration with the V5 monitoring/SNS package.

- Added a non-destructive operational drill CLI for controlled Batch failure,
  bad-data isolation, corrected replay, duplicate replay and CDC retained-history
  replay.
- AWS writes are disabled by default and require explicit `execute --execute`.
- All new Batch objects are restricted to
  `batch/v5-drill/<unique-v5-run-id>/`; no delete operation exists.
- Glue-compatible leaf names begin with `broker_claims`. Bad input is baseline
  plus one invalid claim; recovery is baseline plus the corrected unique claim;
  replay is byte-identical to recovery. This preserves the current full-snapshot
  `createOrReplace` semantics without shrinking trusted tables.
- Added focused regression tests for fixture integrity, encryption parameters,
  safety latch, Batch reconciliation and CDC current-state idempotency.
- Added actionable Batch/Glue/DQ/quarantine/replay/CDC runbooks and exact DEV
  execution/validation commands.
- The real drill must use MFA Human -> Operator -> DataEngineer and correlate
  Step Functions failure with infrastructure alarm/SNS evidence.
- No Terraform, AWS resource, RDS row, DMS task or accepted data was modified by
  this Worker.

Last updated: 2026-09-15.
