# V1 ML Data QA

## Scope

This review covers the 120-row deterministic `claim_risk_features` population
created by the V1 file-source expansion. It does not treat the legacy four-row
`fraud_label` fixture as analytical evidence.

## Target and prediction time

- Prediction event: claim submission.
- Feature cutoff: `submitted_at` (`prediction_timestamp` for feature
  construction and the source of `as_of_date`).
- Target: `high_risk_claim`, a future synthetic high-severity/high-cost outcome
  observed after submission.
- `outcome_severity` is a label-supporting outcome and is never an input.
- The Gold prediction output must distinguish the feature cutoff/as-of value
  from the timestamp when scoring was executed.

## Observed population

The deterministic fixture contains 120 claims: 39 positive and 81 negative,
for a positive rate of 32.5%. A chronological 60/20/20 split ordered by
`submitted_at, claim_id` gives:

| Split | Rows | Positive | Negative | Positive rate |
|---|---:|---:|---:|---:|
| Train | 72 | 21 | 51 | 29.17% |
| Validation | 24 | 9 | 15 | 37.50% |
| Test | 24 | 9 | 15 | 37.50% |

All three partitions contain both classes. Training, validation, and test must
be separated chronologically rather than by a random/hash split so later
claims cannot enter an earlier training population.

## Leakage controls

Allowed inputs are values known at submission: submitted claim amount,
reporting delay, product/broker/reference attributes whose source snapshot is
not newer than the claim, coverage attributes, and vehicle/region risk
attributes. Direct identifiers remain only in the sidecar manifest.

The model matrix must exclude:

- `high_risk_claim` except as the label-first training column;
- `outcome_severity`;
- `approved_amount` and `paid_amount`;
- final claim status or investigation result;
- settlement duration;
- any update or reference version newer than `submitted_at`;
- customer PII and free-text claim description.

Every current reference file has `source_updated_at = 2026-08-01T00:00:00Z`,
which precedes the earliest claim submission. This makes the current snapshot
safe for the V1 run. A future multi-version implementation must enforce the
cutoff in the join itself; the current join relies on the single pre-dated
snapshot.

## Learnability and noise

Univariate checks show useful but non-perfect relationships:

| Numeric input | Univariate AUC |
|---|---:|
| Claim amount | 0.7705 |
| Weather risk score | 0.7597 |
| Catastrophe risk score | 0.7075 |
| Accident risk score | 0.4340 |

No reviewed numeric input individually determines the label. The generator
adds uniform random noise to a multivariable latent-risk score, so an
artificially perfect test score is not expected and should trigger review.

## Known V1 limitations

- `natural_hazard_risk_score` currently duplicates
  `catastrophe_risk_score`; only one should enter the model matrix.
- Only three immutable OLTP policy/customer combinations support the 120
  claims. Product, broker, and vehicle categorical variation is consequently
  limited.
- Actual coverage tiers in the training population are `STANDARD` and
  `ULTIMATE`; categorical encoding must preserve both or provide an explicit
  unknown level.
- Vehicle repair band, theft band, and vehicle risk category have only one
  non-null level in this fixture and carry little independent evidence.
- Metrics are V1 synthetic-data evidence, not estimates of production
  insurance performance.

## Acceptance checklist

- [x] Effective training and transform quotas are both at least 1.
- [x] Export contains 120 unique `claim_id` values and no missing required
  feature values after documented imputation.
- [x] Chronological splits match 72/24/24 with 21/9/9 positives.
- [x] Feature names and target definition are persisted with the model run.
- [x] Training and validation inputs are headerless, label-first numeric CSV;
  transform input is headerless numeric CSV without the label.
- [x] Validation and independent test AUC plus log loss, accuracy, precision,
  recall, and F1 are reported.
- [x] Exactly one prediction is materialized per input claim and model version.
- [x] `high_risk_probability` is in `[0,1]`; `risk_level`, `model_version`,
  scoring timestamp, feature as-of value, and run ID are populated.
- [x] The transient training and transform compute reaches a terminal state;
  no endpoint or notebook exists.
