-- The outcome label is retained for supervised training but must be removed from X.
SELECT high_risk_claim, COUNT(*) AS row_count,
       AVG(CAST(claim_amount AS DOUBLE)) AS average_submission_amount,
       AVG(CAST(accident_risk_score AS DOUBLE)) AS average_accident_risk,
       AVG(CAST(natural_hazard_risk_score AS DOUBLE)) AS average_hazard_risk
FROM claim_risk_features
GROUP BY high_risk_claim
ORDER BY high_risk_claim;

-- Referential completeness for the enriched training-ready rows.
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS missing_product,
    SUM(CASE WHEN broker_id IS NULL THEN 1 ELSE 0 END) AS missing_broker,
    SUM(CASE WHEN claim_type_id IS NULL THEN 1 ELSE 0 END) AS missing_claim_type,
    SUM(CASE WHEN incident_region_code IS NULL THEN 1 ELSE 0 END) AS missing_region,
    SUM(CASE WHEN coverage_code IS NULL THEN 1 ELSE 0 END) AS missing_coverage
FROM claim_risk_features;
