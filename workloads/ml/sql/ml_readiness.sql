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

-- Point-in-time contract: prediction time is claim submission time for V1.
-- Current reference snapshots must not be newer than the prediction record.
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN submitted_at IS NULL THEN 1 ELSE 0 END) AS missing_prediction_timestamp,
    SUM(CASE WHEN incident_date > CAST(submitted_at AS DATE) THEN 1 ELSE 0 END) AS future_incident_date,
    SUM(CASE WHEN claim_amount < 0 THEN 1 ELSE 0 END) AS invalid_claim_amount
FROM claim_risk_features;

-- Use these boundaries for the reproducible chronological 60/20/20 split.
-- The ML export must retain claim_id and submitted_at in a sidecar manifest,
-- while the XGBoost matrices remain numeric and label-first/headerless.
WITH ranked AS (
    SELECT
        claim_id,
        submitted_at,
        high_risk_claim,
        ROW_NUMBER() OVER (ORDER BY submitted_at, claim_id) AS row_number,
        COUNT(*) OVER () AS total_rows
    FROM claim_risk_features
), partitioned AS (
    SELECT *,
        CASE
            WHEN row_number <= CAST(FLOOR(total_rows * 0.60) AS BIGINT) THEN 'train'
            WHEN row_number <= CAST(FLOOR(total_rows * 0.80) AS BIGINT) THEN 'validation'
            ELSE 'test'
        END AS split_name
    FROM ranked
)
SELECT
    split_name,
    COUNT(*) AS row_count,
    SUM(CASE WHEN high_risk_claim = 1 THEN 1 ELSE 0 END) AS positive_count,
    AVG(CAST(high_risk_claim AS DOUBLE)) AS positive_rate,
    MIN(submitted_at) AS min_prediction_timestamp,
    MAX(submitted_at) AS max_prediction_timestamp
FROM partitioned
GROUP BY split_name
ORDER BY min_prediction_timestamp;
