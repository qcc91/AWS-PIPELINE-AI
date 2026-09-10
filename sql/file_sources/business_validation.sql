-- Run against the DEV Gold database after the expanded broker_claims.csv finishes.
-- Claims by category and incident risk band.
SELECT claim_category, overall_risk_band, COUNT(*) AS claim_count,
       SUM(claim_amount) AS total_claim_amount
FROM fact_claim_enriched
GROUP BY claim_category, overall_risk_band
ORDER BY total_claim_amount DESC;

-- Policy count, written premium, claim volume, and non-duplicated loss ratio by product category.
SELECT product_category, COUNT(DISTINCT policy_id) AS policy_count,
       SUM(annual_premium_amount) AS written_premium,
       SUM(claim_count) AS claim_count,
       SUM(total_approved_amount) / NULLIF(SUM(annual_premium_amount), 0) AS loss_ratio
FROM policy_performance
GROUP BY product_category
ORDER BY written_premium DESC;

-- Broker/branch/region performance. Premium is aggregated from one row per policy.
SELECT broker_id, broker_name, branch_id, branch_name, broker_region_code,
       active_policy_count, total_annual_premium, claim_count, loss_ratio
FROM broker_performance
ORDER BY total_annual_premium DESC;

-- Coverage and vehicle risk cuts for BI.
SELECT coverage_tier, COALESCE(vehicle_risk_category, 'NOT_APPLICABLE') AS vehicle_risk_category,
       COUNT(*) AS claim_count, SUM(claim_amount) AS total_claim_amount
FROM fact_claim_enriched
GROUP BY coverage_tier, COALESCE(vehicle_risk_category, 'NOT_APPLICABLE')
ORDER BY total_claim_amount DESC;
