# V6B Feature Store + Unified Studio MLflow completion review

## Result

V6B implementation is complete on DEV and ready for Human pull-request review.
No PROD ML resource, endpoint, notebook, online Feature Store, new Unified Studio
domain/project, release tag or V7 work was created.

## Managed Feature Store and Pipeline evidence

- Feature Group: `insurance-dev-claim-risk-features`
- Feature Group state: `Created`; Offline Store `Active`; Online Store disabled
- Glue catalog: `insurance_dev_control.claim_risk_features_offline`
- Managed Pipeline: `insurance-dev-claim-risk`
- Accepted execution: `zr3k4aa3lzfz` (`Succeeded`)
- Managed steps: 9/9 succeeded
- Feature records: 120 submitted / 120 materialized / 120 read back
- Training source: Offline Store readback
- Split: 72 train / 24 validation / 24 chronological test rows
- Test metrics: AUC 0.622222, accuracy 0.625, log loss 0.656316
- Model package: `insurance-dev-claim-fraud/2`
- Gold validation: 120 rows / 120 unique claims / 0 invalid probabilities

The managed DAG is:

```text
PrepareData -> MaterializeFeatureStore -> TrainXGBoost -> EvaluateModel
            -> ModelQualityGate -> RegisterModel -> CreateBatchModel
            -> BatchTransform -> PublishAndValidateGold
```

## Managed MLflow and Unified Studio evidence

- Tracking server: `insurance-dev-claim-risk`
- Size/version: `Small`, MLflow 3.0.0
- Artifact root: `s3://aip-insurance-dev-control-dev01/mlflow`
- Unified Studio/DataZone connection: `insurance-dev-claim-risk-mlflow`
  (`490c7mbswsmzhe`)
- Existing domain/project: `dzd-cvpo8yttzkms0y` / `d1zzpm6mte659e`
- Experiment: `insurance-claim-risk`
- Evidence run: `e5caa62c88374b0c87b988394ef5dfee`
- Logged Pipeline execution: accepted V6 execution `g46dxu0f1ydw`
- Idempotent repeat logging: passed
- Final server state: `Stopped/Inactive`

MLflow records the real managed Pipeline evidence; it is not a second training
orchestration system.

## Security, cost and infrastructure

- Existing KMS key and control bucket are reused.
- Feature Store and MLflow roles are resource/prefix scoped.
- No long-lived credential was added.
- Offline-only Feature Store adds no continuously running feature-serving cost.
- The first Small MLflow runtime remained active approximately 14h52m, exceeding
  the approved four-hour window. At USD 0.642/hour, estimated compute is about
  USD 9.55 plus negligible storage. It is stopped and no longer accruing compute.
- V6B-scoped Terraform final plan: `No changes`.
- The unscoped DEV foundation plan showed unrelated repository-refactor
  source/path and line-ending drift (`2 add / 9 change / 2 destroy`). It was not
  applied; the two planned replacements were outside V6B.

## Validation

- Focused V6B tests: 27/27 passed
- Full automated suite: 151/151 passed
- Terraform: all seven roots initialized with backend disabled and validated
- Repository consistency and high-confidence credential scan: passed
- Terraform formatting and Git whitespace checks: passed

## Remaining gate

Create the V6B pull request and let protected GitHub Actions run. Do not merge,
tag, deploy to PROD or begin V7 without separate Human approval.
