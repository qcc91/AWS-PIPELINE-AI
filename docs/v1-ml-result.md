# V1 ML Happy Path Result

## Status

V1 ML completed in `ap-southeast-2` on 2026-09-10 from the real 120-row Gold
`claim_risk_features` table. Effective quotas were Training 15 and Transform 8;
the run still used only one `ml.m5.large` for each job. The old four-row
`fraud_label` smoke fixture was not used.

No endpoint, notebook, domain, warm pool, or other persistent ML compute was
created. The temporary SageMaker Model was deleted after Gold publication; the
encrypted model artifact remains in S3.

## Target, features, and leakage controls

The target is `high_risk_claim`: a synthetic future high-severity or high-cost
outcome observed after claim submission. Prediction time is `submitted_at`.
Rows are split chronologically by `submitted_at, claim_id`.

The executed 54-column matrix contains claim amount, reporting delay, broker
experience, four regional risk scores, deductible, coverage limit/option flag,
vehicle value/safety/age, and one-hot product, broker, claim category, region,
coverage, repair/theft, and vehicle-risk categories. Exact order is defined in
`src/ml/claim_risk.py`. `natural_hazard_risk_score` was removed because it
duplicated catastrophe risk in this fixture.

Approved/paid amounts, final claim status, outcome severity, settlement
duration, update timestamps, and the target are excluded. The sidecar preserves
`claim_id`, `as_of_date`, `feature_version`, split, and label.

| Partition | Rows | Positive | Negative |
|---|---:|---:|---:|
| Train | 72 | 21 | 51 |
| Validation | 24 | 9 | 15 |
| Test | 24 | 9 | 15 |
| Total | 120 | 39 | 81 |

Single-field AUC was below perfect discrimination (`claim_amount` 0.7705,
weather 0.7597, catastrophe 0.7075), confirming learnable but noisy data.

## Runtime result

- Training Job `insurance-dev-claim-risk-v1-20260910-061552-r2`: Completed,
  130 billable seconds, Training AUC 0.95518, Validation AUC 0.65556.
- Independent Test: AUC 0.62222, log loss 0.65632, accuracy 0.625, precision 0,
  recall 0, F1 0 at the predeclared 0.50 threshold.
- Model artifact:
  `s3://aip-insurance-dev-control-dev01/ml/runs/insurance-dev-claim-risk-v1-20260910-061552/model-output-r2/insurance-dev-claim-risk-v1-20260910-061552-r2/output/model.tar.gz`.
- Transform Job `insurance-dev-claim-risk-v1-20260910-061552-r2-transform`:
  Completed, 120 predictions.
- Glue Run `jr_0fd5952dd2753857e716927329d51567054b596ddcae48ba2cfbe2421660185f`:
  Succeeded, 194 DPU-seconds.

Gold `insurance_dev_gold.claim_risk` has 120 rows and 120 distinct claims, no
null probabilities, range 0.36053–0.60398, and preserved as-of/version/prediction
timestamps. All predictions fall into the predeclared MEDIUM band (0.30–0.70),
which is reported as a calibration/threshold limitation rather than tuned away.

Athena evidence: summary `35eabe11-406e-4231-b2d7-6fa01107ea31`, bands
`d8ca8dbd-f820-4267-b809-2093545aabe9`, representative rows
`5e26c0f5-1947-43d7-a0ae-69cc250ea6ee`.

## Issues, cost, and limitations

Local launch fixes added the login CRT dependency and pinned `sagemaker<3` for
the v2 `image_uris` interface. AWS built-in XGBoost rejected custom metric
definitions, so the runner uses AWS-provided metrics. The first real Training
Job used 130 billable seconds but failed during artifact upload; the runner now
passes the existing platform KMS key to Training and Transform output instead
of weakening the control-bucket policy.

Including failed and successful Training, Transform, Glue, Athena, and small S3
requests, estimated incremental cost is USD 0.04–0.05. There is no new fixed
monthly compute cost.

The sample is small, uses only three OLTP policy/customer anchors, and contains
constant/low-variance columns. The train/validation gap, zero Test F1 at 0.50,
and one risk band mean this is functional V1 evidence, not a production model.
