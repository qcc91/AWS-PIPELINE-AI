-- V1 BI aggregate; reconciliation source for claim KPIs.
SELECT event_date, claim_status, claim_count, total_claim_amount,
       total_approved_amount, currency_code
FROM insurance_dev_gold.claim_daily_summary;
