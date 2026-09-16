# V5 Data Operational Drill

## Objective and boundaries

This drill proves a compact DEV sequence: fail -> detect/audit -> correct ->
replay -> reconcile. It reuses V2 Batch/CDC reliability and V3 roles. It creates
no AWS resources, changes no RDS rows, restarts no DMS task, deletes no data and
introduces no long-lived credentials. Monitoring/SNS evidence is supplied by
the V5 infrastructure package; Step Functions failure is the shared primary
alarm signal.

## Local preparation

Use the accepted synthetic expanded feed as the recovery baseline:

```powershell
$runId = & python scripts/v5/operational_drill.py prepare --baseline data/file_sources/broker_claims.csv --output .v5-drill
$manifest = $runId.Trim()
python -m pytest -q tests/data/test_v5_operational_drill.py tests/data/test_v2_reliability.py
```

The command returns the manifest path. Generated artifacts are local and
ignored only when `.v5-drill/` is excluded from Git; verify `git status --short`
before any commit. `broker_claims_v5_bad.csv` contains the complete baseline
plus one synthetic negative-amount claim. `broker_claims_v5_recovery.csv`
contains the complete baseline plus the same uniquely identified claim corrected
to a positive amount. `broker_claims_v5_duplicate_replay.csv` is byte-identical
to recovery. Keeping the baseline is required because the current Batch job
publishes a complete snapshot with `createOrReplace`; a one-row file would
incorrectly shrink trusted Silver/Gold.

Establish the normal MFA Human -> Operator -> DataEngineer role session in one
PowerShell process. Do not print or persist the returned credentials. Confirm
the final ARN ends in `assumed-role/insurance-dev-data-engineer-role/...`.

```powershell
aws login --profile aip-dev-human
$op = aws sts assume-role --profile aip-dev-human --role-arn arn:aws:iam::199476069493:role/insurance-dev-operator-role --role-session-name v5-ops --query Credentials --output json | ConvertFrom-Json
$env:AWS_ACCESS_KEY_ID=$op.AccessKeyId; $env:AWS_SECRET_ACCESS_KEY=$op.SecretAccessKey; $env:AWS_SESSION_TOKEN=$op.SessionToken
$de = aws sts assume-role --role-arn arn:aws:iam::199476069493:role/insurance-dev-data-engineer-role --role-session-name v5-data-drill --query Credentials --output json | ConvertFrom-Json
$env:AWS_ACCESS_KEY_ID=$de.AccessKeyId; $env:AWS_SECRET_ACCESS_KEY=$de.SecretAccessKey; $env:AWS_SESSION_TOKEN=$de.SessionToken
Remove-Variable op,de
aws sts get-caller-identity --region ap-southeast-2
$kmsArn = aws kms describe-key --region ap-southeast-2 --key-id alias/insurance/dev/platform-data --query KeyMetadata.Arn --output text
```

Before every mutation, inspect the rendered command by replacing `execute`
with `show-command`. Actual AWS writes require the explicit `--execute` latch.

## Real DEV sequence

### 1. Baseline

Capture trusted counts before the drill using the Athena queries below. Also
record the latest successful Batch execution and current alarm state. Never
copy query rows containing PII into evidence.

### 2. Missing-input failure

```powershell
python scripts/v5/operational_drill.py show-command --manifest $manifest --scenario missing-input
python scripts/v5/operational_drill.py execute --manifest $manifest --scenario missing-input --execute
```

Expected: the named Step Functions execution reaches `FAILED`; Bronze reports
`NoSuchKey`; `bronze-failure.json` exists. The failure alarm becomes `ALARM` and
the shared SNS path records delivery/notification evidence. Do not create the
missing object until the failure and alert evidence are captured.

### 3. Bad-data isolation

```powershell
python scripts/v5/operational_drill.py show-command --manifest $manifest --scenario bad-batch --kms-key-arn $kmsArn
python scripts/v5/operational_drill.py execute --manifest $manifest --scenario bad-batch --kms-key-arn $kmsArn --execute
```

S3 EventBridge starts the normal workflow. Locate the execution whose input
contains the manifest's `bad_batch` key. For baseline count `B`, expected Silver
reconciliation is `B+1 = B output + 1 rejected + 0 duplicate`. Trusted Gold
remains at `B` rows, and the drill claim ID is absent.

### 4. Corrected recovery

```powershell
python scripts/v5/operational_drill.py execute --manifest $manifest --scenario recovery --kms-key-arn $kmsArn --execute
```

Expected: normal EventBridge/Step Functions path succeeds with `B+1` valid
outputs, no rejection and no duplicate. Gold contains the unique corrected
claim with a positive amount and has `B+1` rows. This proves actual correction
and promotion rather than treating an old baseline as recovery.

### 5. Duplicate replay

```powershell
python scripts/v5/operational_drill.py execute --manifest $manifest --scenario duplicate-replay --kms-key-arn $kmsArn --execute
```

Expected: successful `DUPLICATE` no-op with the same content SHA-256 as the
recovery file: input `B+1`, output `0`, rejected `0`, duplicate `B+1`. Gold
remains at `B+1` unique claims.

### 6. CDC retained-history replay

Discover, but do not alter, one existing DMS object and pass its exact key:

```powershell
$cdcKey = aws s3api list-objects-v2 --region ap-southeast-2 --bucket aip-insurance-dev-landing-dev01 --prefix oltp/public/claims/ --max-items 10 --query 'reverse(sort_by(Contents,&LastModified))[0].Key' --output text
python scripts/v5/operational_drill.py show-command --manifest $manifest --scenario cdc-replay --cdc-object-key $cdcKey
python scripts/v5/operational_drill.py execute --manifest $manifest --scenario cdc-replay --cdc-object-key $cdcKey --execute
```

Expected: CDC state machine succeeds by rebuilding current state from retained
history. Current Gold business keys and expected insert/update/delete outcomes
remain unchanged. This is change-log-to-current-state reconciliation, not the
Batch row equation. Do not restart the pre-existing failed DMS task for V5.

## Evidence collection

For each execution record UTC start/end, execution ARN, input object key, Glue
run IDs, stage statuses and S3 audit keys. Find EventBridge-started execution
inputs with `list-executions` followed by `describe-execution`; use the object
key in the manifest as the correlation value.

```powershell
aws stepfunctions list-executions --region ap-southeast-2 --state-machine-arn arn:aws:states:ap-southeast-2:199476069493:stateMachine:insurance-dev-batch-claim-lakehouse --max-results 25
aws stepfunctions describe-execution --region ap-southeast-2 --execution-arn <execution-arn>
aws s3 ls s3://aip-insurance-dev-control-dev01/control/v2/pipeline_runs/<run_id>/ --recursive
aws s3 ls s3://aip-insurance-dev-quarantine-dev01/quarantine/v2/batch/claim/<run_id>/ --recursive
```

Download only non-sensitive audit JSON to a temporary directory and validate
the Batch equation locally:

```powershell
python scripts/v5/operational_drill.py validate-audit --file <silver-audit.json>
```

Expected output is `{"valid": true, "errors": []}`.

## Athena acceptance queries

Run in the existing encrypted `insurance-dev-bi` workgroup.

```sql
SELECT count(*) AS rows, count(DISTINCT claim_id) AS unique_claims
FROM insurance_dev_gold.fact_claim;

SELECT count(*) AS negative_rows
FROM insurance_dev_gold.fact_claim
WHERE claim_amount < 0;

SELECT claim_id, claim_amount
FROM insurance_dev_gold.fact_claim
WHERE claim_id = '<manifest.drill_claim_id>';

SELECT count(*) AS rows, count(DISTINCT claim_id) AS unique_claims
FROM insurance_dev_gold.fact_claim_cdc;

SELECT claim_id, claim_status, approved_amount
FROM insurance_dev_gold.fact_claim_cdc
WHERE claim_id IN ('clm_7001', 'clm_7003')
ORDER BY claim_id;

SELECT count(*) AS deleted_payment_rows
FROM insurance_dev_silver.payments
WHERE payment_id = 'pay_8001';
```

Acceptance: immediately after bad input, Batch remains at the captured baseline
`B`, the drill claim is absent and `negative_rows=0`. After recovery and replay,
`rows=unique_claims=B+1`, the drill claim appears once with `101.00`, and
`negative_rows=0`. CDC retains its captured baseline and expected historical
insert/update/delete outcomes. If live CDC baseline differs, preserve and
reconcile its exact before/after state rather than forcing a historical count.

## Completion criteria and cost

- Missing input failed with Step Functions, audit and alarm/SNS evidence.
- Bad row was quarantined; trusted layers were uncontaminated.
- Corrected input and duplicate replay completed without duplicate state.
- Batch audit equation passed; CDC current-state semantics passed.
- Athena returned expected trusted counts and business-key uniqueness.
- No object/table/snapshot was deleted and no RDS/DMS state was changed.

The toolkit adds no fixed cost. Real validation incurs only short existing Glue,
Step Functions, S3, CloudWatch/SNS and Athena usage. Stop if the Manager's cost
review identifies a material FREE-plan impact.
