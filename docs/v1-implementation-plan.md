# V1 practical implementation plan

## Repository reuse map

- Reuse now: approved architecture/data contracts; Terraform DEV/PROD roots;
  state bootstrap; VPC/private subnets/S3 endpoint; KMS/S3 modules; basic IAM;
  Glue Catalog; Lake Formation and audit modules; static plan manifest/tests.
- Complete locally: Terraform formatting and provider-backed DEV validation.
- Partial/blocking: no AWS resources exist; real plans await a non-root AWS
  session, account/VPC/IAM discovery and exact role ARNs.
- Not started: executable batch, CDC, streaming, Iceberg transformations,
  Athena/QuickSight, SageMaker and RAG paths.
- Leave untouched unless blocking V1: existing remote-state, governance,
  CloudTrail, retention and security-hardening code that mainly belongs to
  V3–V5.

## Work packages

1. `V1-INFRASTRUCTURE`: finish current Terraform package, obtain trustworthy
   bootstrap/foundation plans, receive Human plan approval, apply DEV only, and
   run smoke checks.
2. `V1-BATCH-LAKEHOUSE`: implement CSV landing, EventBridge/Step Functions/
   Glue happy path and Bronze/Silver/Gold Iceberg for the core entities and Gold
   outputs needed by the demo.
3. `V1-CDC`: implement small RDS PostgreSQL source, DMS full load plus INSERT/
   UPDATE/DELETE CDC, Bronze ingestion and Silver current-state/Gold updates.
4. `V1-STREAMING`: implement Python producer, Kinesis, Firehose, Bronze events
   and minimal Silver/Gold event outputs.
5. `V1-BI`: expose Gold through Athena and build the minimum QuickSight demo.
6. `V1-ML`: train/evaluate XGBoost from Gold claim data and run batch inference
   to the claim-risk output.
7. `V1-RAG`: ingest approved insurance documents into Bedrock Knowledge Bases
   with S3 Vectors and demonstrate a cited answer.
8. `V1-DEMO-INTEGRATION`: execute the complete DEV happy path, capture tests,
   costs and known limitations, then present V1 completion for Human review.

Workers resolve normal implementation and test failures autonomously. Manager
reviews each meaningful integration boundary. The immediate Human gate is the
Terraform plan approval before any AWS-changing operation.
