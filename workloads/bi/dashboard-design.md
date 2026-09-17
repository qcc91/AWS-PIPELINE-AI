# V1 QuickSight dashboard design

When the account prerequisites are approved, create one analysis/dashboard
from the `fact_claim` dataset and add:

- KPI: total claim amount (`SUM(claim_amount)`)
- KPI: approved amount (`SUM(approved_amount)`)
- KPI: claim count (`COUNT(claim_id)`)
- Bar chart: claim count by `claim_status`
- Table: `claim_id`, `claim_status`, `claim_amount`, `approved_amount`,
  `submitted_at`

Use `claim_daily_summary` as the optional aggregate dataset for trend charts.
The design intentionally excludes claim descriptions and direct customer PII.
