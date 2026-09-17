# V1 Batch Happy Path result

Status: **COMPLETE** on 2026-09-09 in DEV (`ap-southeast-2`).

## Real execution

- Input: `s3://aip-insurance-dev-landing-dev01/batch/broker_claims-v1.csv`
- Step Functions execution: `2d7cdc10-e77b-ca90-16fb-515c38629245_9b70b01d-6953-28c8-edc7-1b7645fcf452` — `SUCCEEDED`
- Glue run: `jr_b811c71548f596a7b60b3125ec8e20e36bcfa19e2adcbb5c2c1384a9c0a815ba` — `SUCCEEDED`, 82 seconds, 165 DPU-seconds
- Terraform apply: 14 created, 0 changed, 0 destroyed
- Terraform post-apply plan: no changes

## Data verification

| Layer/table | Result |
|---|---:|
| `insurance_dev_bronze.claim` | 3 rows |
| `insurance_dev_silver.claim` | 3 rows |
| `insurance_dev_gold.fact_claim` | 3 rows |
| `fact_claim` total claim amount | 5290.50 |
| `fact_claim` total approved amount | 800.00 |

`insurance_dev_gold.claim_daily_summary` returned:

| Status | Claims | Claim amount | Approved amount |
|---|---:|---:|---:|
| APPROVED | 1 | 840.50 | 800.00 |
| SUBMITTED | 1 | 1250.00 | 0.00 |
| UNDER_REVIEW | 1 | 3200.00 | 0.00 |

Athena query IDs: Bronze `56156921-3c4c-493c-ac60-52f2bb875966`, Silver
`a7f027d3-350e-495a-adc2-5a495d68cd24`, fact
`d99767a4-5744-4815-9c58-d0a6d824f0a5`, summary
`0130b935-fdc0-4a4a-83ab-11cca8257501`.

## Cost, security, and deviations

The Glue run consumed 165 DPU-seconds (0.04583 DPU-hours), approximately
USD 0.0202 at the planning rate of USD 0.44/DPU-hour. S3, Athena, EventBridge,
Step Functions, and log usage for this three-row run are negligible relative
to the approved USD 12/month review threshold. No always-on compute was added.

There was no final resource deviation from the approved plan. The existing AWS
CLI login expired before the first attempt, so the Human reauthenticated and
the plan was regenerated before apply. No credentials were persisted or
printed. Temporary root execution remains the Human-approved V1 shortcut;
least-privilege separation remains required in V3.

V1 intentionally excludes V2 completion-ledger, quarantine, retry,
deduplication, and reconciliation hardening.
