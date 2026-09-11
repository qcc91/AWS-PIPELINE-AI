# V2 Data Reliability — Batch/File and PostgreSQL CDC

## Scope

Batch/File and PostgreSQL Full Load + CDC are two ingestion mechanics feeding
one shared Bronze/Silver/Gold lakehouse. This package adds V2 failure safety,
idempotency, DQ, quarantine, audit and reconciliation. It does not redesign DMS,
create one job per table, or implement V3–V5 controls.

## Processing boundaries

Both paths reuse one script entry point per ingestion pattern and expose three
independent Glue jobs through `--PROCESSING_STAGE=bronze|silver|gold`:

1. Bronze preserves source data plus stable identity and source metadata.
2. Silver owns contract/DQ gates, quarantine, deterministic deduplication and
   current-state semantics.
3. Gold deterministically replaces business facts/aggregates from trusted
   Silver state.

Step Functions owns stage ordering, bounded transient retry and Catch/failure.
This grouping provides useful failure/retry/audit boundaries without multiplying
jobs by entity.

## Batch/File contract

- Content SHA-256 is `source_file_id`; an S3 key rename does not create a new
  logical file.
- Bronze stores `_source_file_id`, `_record_hash`, `_run_id`, source URI,
  ingestion time and schema version.
- Silver checks the existing claim schema and meaningful claim rules: required
  keys, supported status, ISO currency, date order, nonnegative amounts, and
  approved amount not exceeding claimed amount.
- Invalid rows are written under
  `quarantine/v2/batch/<entity>/<run_id>/` with the source record, failed rule,
  source, entity, run ID and rejection timestamp.
- Valid duplicate business keys retain the newest `updated_at`, with record hash
  as a deterministic tie break.
- Gold writes the processed-file marker only after successful publication.
  Replaying completed content is a traceable no-op.
- Batch reconciliation is
  `input = output + rejected + duplicate`.

Reference files use the same stage boundary. Their primary key is required and
newest `source_updated_at` wins deterministically.

## CDC contract

- DMS remains Full Load + CDC to S3 CSV.
- Bronze normalizes `I/U/D`, source order and a SHA-256 `source_change_id`, then
  removes exact replayed changes.
- Invalid keys, operations, ordering metadata, negative amounts and invalid
  date ordering are isolated under `quarantine/v2/cdc/<table>/<run_id>/`.
- Silver chooses one latest change per business key using source order followed
  by stable change ID. A latest `D` tombstone removes the row. Replaying the
  same history therefore produces the same current state.
- Silver retains change identity/order metadata for recovery comparisons; Gold
  removes operational fields from business facts.
- CDC reconciliation is explicitly change-log-to-current-state, not the Batch
  row-count equation. Audit records change input, exact replay duplicates,
  rejected changes, and current-state output.

## Control records

Each stage writes JSON to
`control/v2/pipeline_runs/<run_id>/<stage>.json`. Records contain pipeline,
source, stage, status, counts, error, reconciliation type/result and stable
source identity where applicable. Completed Batch files also write
`control/v2/processed_files/<source_file_id>.json`.

These are operational controls, not business lakehouse tables. The design uses
the existing control and quarantine buckets and adds no continuously billed
resource.

## Focused local evidence

The V2 tests cover stable file identity, duplicate-file no-op, invalid-row
quarantine, within-file deduplication, Batch reconciliation, CDC I/U/D,
out-of-order changes, exact replay, deterministic equal-time ordering, invalid
CDC quarantine and stage-interface presence.

## Real AWS validation

All cases below ran in `ap-southeast-2` against the deployed DEV platform on
2026-09-11.

- Normal Batch run `372a8edc-4e08-0397-cefb-aee8af0c16c6`: Bronze, Silver and
  Gold succeeded with `input=120, output=120, rejected=0, duplicate=0`.
- Same bytes under another key, run
  `dd8f3e40-573b-86ab-d458-7faebd00b1a4`, resolved to the same SHA-256
  `ede17ff9...98f6b`. All stages returned `DUPLICATE` with `input=120,
  output=0, duplicate=120`; Athena query
  `435b7ad1-6b0f-4dbc-97f7-9c45824c86b7` confirmed 120/120 unique Gold claims.
- DQ run `991f0dba-bb59-bf08-d29b-b6a02fc76983` supplied 120 valid rows plus
  one new negative-amount claim. Silver recorded `input=121, output=120,
  rejected=1`, quality score `0.991736` and a passing reconciliation. The
  rejected JSON is retained under
  `quarantine/v2/batch/claim/<run_id>/`; Athena confirmed the invalid claim is
  absent and Gold remains 120/120 unique.
- Missing-object run `v2-batch-controlled-failure-20260911` failed once in
  Bronze with `NoSuchKey`, wrote both the Glue stage audit and orchestrator
  `bronze-failure.json`, and did not retry the deterministic task. Supplying the
  object then produced successful recovery run
  `f2aa471c-2bea-43c4-39cd-f618f97b90d5`, classified as a safe duplicate.
- CDC runs `v2-cdc-replay-a-20260911` and `v2-cdc-replay-b-20260911` both
  completed Bronze/Silver/Gold. Each read 14 retained changes; Silver recorded
  11 current-state outputs and 2 exact/superseded duplicates using
  change-log-to-current-state reconciliation; Gold published three claims.
- Athena query `e1660552-6a53-4f16-a681-c87e2d0666a8` confirmed three unique
  claims, inserted `clm_7003`, and updated `clm_7001` to `APPROVED/450.00`.
  An initial validation query contained a deterministic VARCHAR/DECIMAL
  comparison error; the corrected query above passed. Payment validation
  confirmed deleted `pay_8001` is absent and the
  current table contains zero rows, consistent with the one-row source baseline.

## Known V2 limits

- Control JSON is intentionally small and S3-based; it is not an enterprise
  metadata database.
- CDC rebuilds current state from the small retained DMS history. Incremental
  watermark optimization is unnecessary at the project data volume.
- Detailed referential DQ is limited to relationships already enforced by the
  PostgreSQL source and the shared trusted joins. Broader governance belongs to
  later versions.
