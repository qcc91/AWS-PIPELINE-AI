-- V1 BI source view/query: no direct PII, Gold contract columns only.
SELECT claim_id, claim_status, claim_amount, approved_amount,
       currency_code, incident_date, submitted_at, updated_at,
       policy_id, customer_id
FROM insurance_dev_gold.fact_claim;
