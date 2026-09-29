# V6B Managed MLflow operations

## Scope and ownership

V6B adds experiment tracking to the existing DEV claim-risk workflow. The
SageMaker Pipeline `insurance-dev-claim-risk` remains the orchestrator; MLflow
records evidence and does not replace the managed Pipeline DAG. Terraform
creates no endpoint, notebook, new domain, new project, or PROD resource.

Durable resources are:

- one `Small` SageMaker Managed MLflow Tracking Server named
  `insurance-dev-claim-risk`;
- one least-privilege service role that can use only
  `s3://aip-insurance-dev-control-dev01/mlflow/` and the existing platform KMS
  key through regional S3;
- one project-scoped DataZone connection named
  `insurance-dev-claim-risk-mlflow` in existing domain
  `dzd-cvpo8yttzkms0y` and project `d1zzpm6mte659e`;
- exact MLflow run-writing permissions on the existing DEV `MLEngineer` role.

The tracking server has `AmazonDataZoneProject=d1zzpm6mte659e`. The current
AWS-managed `SageMakerStudioProjectRoleMachineLearningPolicy` authorizes MLflow
UI and server actions only when that resource tag matches the project role's
principal tag. The project connection and matching resource tag are both
required for project discovery and access.

## Provider boundary

The HashiCorp AWS provider manages
`aws_sagemaker_mlflow_tracking_server`. The HashiCorp AWS Cloud Control
provider manages `awscc_datazone_connection`, including
`props.mlflow_properties.tracking_server_arn`. There is no manual or CLI-only
connection boundary in this implementation.

The tracking server omits an explicit MLflow version so SageMaker selects the
latest version currently supported by the Sydney tracking-server API. It is
configured as `Small` and has
automatic model registration disabled because the accepted SageMaker Pipeline
continues to own Model Registry registration.

## Cost and four-hour limit

The AWS public price list for `ap-southeast-2`, checked 2026-09-28, reports:

- `Small` tracking server compute: USD 0.642 per running hour;
- backend metadata storage: USD 0.11 per GB-month;
- maximum approved four-hour compute: USD 2.568, plus negligible storage and
  request charges;
- accidental 730-hour continuous runtime: approximately USD 468.66/month.

Stopping the server stops compute charges. Stored metadata and S3 artifacts
remain chargeable at their respective storage rates. Terraform does not model
the operational Started/Stopped state, so creating the server starts it and a
separate explicit stop is mandatory before four elapsed hours.

The first V6B runtime exceeded the approved window: the server was active for
approximately 14h52m and was then verified `Stopped/Inactive`. Estimated Small
compute is approximately USD 9.55, plus negligible metadata/S3 storage. This is
a recorded cost-control deviation. Do not restart the server without a new
explicitly bounded inspection window.

## Plan and apply order

Do not apply until the Human-approved plans have been reviewed. Apply the
bootstrap root first so the non-root Terraform execution role receives the
exact MLflow, DataZone, and Cloud Control permissions. Then plan/apply the DEV
foundation root. Never target PROD.

Expected plan shape when no prior V6B resources exist:

- bootstrap: `0 add / 1 change / 0 destroy`;
- DEV foundation: `4 add / 2 change / 0 destroy`;
- new DEV objects: MLflow IAM role, inline role policy, tracking server, and
  Unified Studio/DataZone connection;
- in-place changes: platform KMS key policy and MLEngineer inline policy.

Both the tracking server and project connection use `prevent_destroy`.

## Runtime controls

Record the creation/start timestamp immediately after apply. Check status with:

```powershell
aws sagemaker describe-mlflow-tracking-server `
  --tracking-server-name insurance-dev-claim-risk `
  --region ap-southeast-2
```

Stop the server as soon as the run and Human UI evidence are captured, and no
later than four elapsed hours:

```powershell
aws sagemaker stop-mlflow-tracking-server `
  --tracking-server-name insurance-dev-claim-risk `
  --region ap-southeast-2
```

Poll `describe-mlflow-tracking-server` until `TrackingServerStatus` is
`Stopped`. Do not use blind start/retry loops. Starting it again requires a
new, explicit cost window:

```powershell
aws sagemaker start-mlflow-tracking-server `
  --tracking-server-name insurance-dev-claim-risk `
  --region ap-southeast-2
```

## Unified Studio verification

In the existing project, navigate:

`Amazon SageMaker Unified Studio -> project d1zzpm6mte659e -> Compute -> AI/ML -> MLflow`

The page must show connection `insurance-dev-claim-risk-mlflow`. Choose
`Open MLflow`, then verify experiment `insurance-claim-risk` contains the real
backfilled run with parameters, actual evaluation metrics, and small artifacts.
The connection or API response alone is not acceptance evidence.

Before apply, and again after apply, verify that the domain and project IDs
resolve, no pre-existing connection with the same name exists, and no other
tracking server will collide. After verification, capture the connection ID,
server ARN/status, experiment/run IDs, pipeline execution ID, Git SHA, and stop
timestamp in the V6B acceptance report.

## Primary references

- [Unified Studio MLflow tracking](https://docs.aws.amazon.com/sagemaker-unified-studio/latest/userguide/use-mlflow-experiments.html)
- [Managed MLflow tracking servers](https://docs.aws.amazon.com/sagemaker/latest/dg/mlflow-create-tracking-server.html)
- [MLflow IAM actions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_sagemaker-mlflow.html)
- [AWS provider tracking server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_mlflow_tracking_server)
- [AWSCC DataZone connection](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/datazone_connection)
- [SageMaker pricing](https://aws.amazon.com/sagemaker/ai/pricing/)
