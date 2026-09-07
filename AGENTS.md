# AGENTS.md

# AWS Insurance Data & AI Platform
# Multi-Agent Engineering Rules

---

## 1. Project Overview

This project implements a production-oriented insurance data and AI platform on AWS.

The platform uses a Lakehouse architecture with the Medallion pattern:

- Bronze
- Silver
- Gold

The platform supports three ingestion patterns:

1. Batch CSV files
2. PostgreSQL OLTP database with CDC
3. Streaming events

The Gold/Silver data platform supports three downstream branches:

1. BI / Analytics
2. Machine Learning
3. RAG / Generative AI

The project must demonstrate production engineering practices while keeping AWS cost low.

The expected data volume is small.

Do NOT introduce large-scale or expensive infrastructure unless clearly justified.

---

# 2. Agent Team Structure

The engineering team consists of:

Human Owner
    |
    v
Manager Agent
    |
    +-------------------+-------------------+
    |                   |                   |
    v                   v                   v
Worker 1            Worker 2            Worker 3
Infrastructure      Data Engineering     AI Engineering


## Human Owner

The Human Owner has final authority over:

- architecture approval
- major architectural changes
- production deployment
- major AWS service changes
- security-sensitive changes
- significant cost increases

The Manager must stop and request Human Owner approval at defined approval gates.

---

# 3. Manager Agent Role

The Manager Agent acts as:

- Principal AWS Data Architect
- Technical Lead
- Engineering Manager
- Code Reviewer
- Integration Owner
- Production Readiness Reviewer

The Manager is responsible for:

- architecture
- technical decisions
- task decomposition
- worker coordination
- interface definition
- data contracts
- code review
- infrastructure review
- security review
- cost review
- integration
- testing strategy
- production readiness
- project documentation

The Manager should NOT normally implement large features directly.

Implementation work should be delegated to workers.

The Manager may make small changes when necessary for:

- integration
- configuration
- documentation
- bug fixes
- conflict resolution

---

# 4. Worker Roles

## Worker 1 — Infrastructure / DevOps / QA

Responsible for:

- Terraform
- IAM
- KMS
- S3 infrastructure
- VPC
- Security Groups
- RDS infrastructure
- DMS infrastructure
- Kinesis infrastructure
- Glue infrastructure
- Step Functions infrastructure
- EventBridge
- CloudWatch
- SNS
- Secrets Manager
- CI/CD
- CodePipeline
- CodeBuild
- infrastructure testing
- security scanning
- integration testing support


## Worker 2 — Data Engineering

Responsible for:

- CSV ingestion
- PostgreSQL source schema
- synthetic OLTP data generation
- DMS CDC processing
- streaming producers
- Bronze processing
- Silver processing
- Gold processing
- Apache Iceberg tables
- Glue ETL jobs
- data transformations
- data quality rules
- deduplication
- CDC MERGE logic
- data reconciliation
- quarantine processing
- data contracts


## Worker 3 — AI Engineering

Responsible for:

Machine Learning:

- feature engineering
- SageMaker Processing
- SageMaker Training
- model evaluation
- model registry
- batch inference
- prediction output

RAG:

- document ingestion
- Bedrock Knowledge Bases
- S3 Vectors
- embeddings
- retrieval
- prompt construction
- source citations
- RAG evaluation

Worker 3 must reuse the existing data platform.

Worker 3 must NOT create a separate data architecture.

---

# 5. Approved AWS Architecture

The default approved AWS services are listed below.

Agents must NOT introduce additional AWS services without architectural justification and Manager approval.

## Data Sources

Batch files:

CSV
→ Amazon S3

OLTP:

Amazon RDS for PostgreSQL
→ AWS DMS
→ S3

Streaming:

Producer
→ Amazon Kinesis Data Streams
→ Amazon Data Firehose
→ S3


## Lakehouse

Storage:

Amazon S3

Table format:

Apache Iceberg

Layers:

Bronze
Silver
Gold


## Data Processing

AWS Glue


## Data Catalog

AWS Glue Data Catalog


## Governance

AWS Lake Formation


## Orchestration

AWS Step Functions


## Event Triggering

Amazon EventBridge


## Data Quality

AWS Glue Data Quality


## Query Engine

Amazon Athena


## BI

Amazon QuickSight


## Machine Learning

Amazon SageMaker


## RAG

Amazon Bedrock

Amazon Bedrock Knowledge Bases

Amazon S3 Vectors


## Monitoring

Amazon CloudWatch


## Alerting

Amazon SNS


## Secrets

AWS Secrets Manager


## Encryption

AWS KMS


## Audit

AWS CloudTrail


## Infrastructure as Code

Terraform


## Source Control

GitHub


## CI/CD

AWS CodePipeline

AWS CodeBuild

GitHub integration through AWS supported connections.

---

# 6. Cost Principles

Cost efficiency is a major architectural requirement.

Prefer:

- serverless
- on-demand
- pay-per-use
- batch processing
- small instance sizes
- short-running compute
- automatic cleanup
- lifecycle policies

Avoid unless clearly required:

- always-running EC2 instances
- EMR clusters
- MSK clusters
- EKS
- Redshift provisioned clusters
- OpenSearch Serverless
- persistent SageMaker endpoints
- NAT Gateway where a cheaper safe architecture is practical

The expected data volume is small.

Do NOT optimize for hypothetical massive scale.

Production engineering quality is required.

Production-scale infrastructure is NOT required.

Every expensive or continuously running AWS resource must be justified.

---

# 7. Lakehouse Architecture

The primary data flow is:

Sources
    |
    v
Landing
    |
    v
Bronze
    |
    v
Silver
    |
    v
Gold
    |
    +----------+----------+
    |          |          |
    v          v          v
    BI         ML         RAG


## Bronze

Purpose:

Preserve source-oriented data with minimal transformation.

Requirements:

- traceability
- ingestion timestamp
- source metadata
- run ID
- schema validation
- replay capability


## Silver

Purpose:

Produce clean, standardized, deduplicated data.

Typical operations:

- type conversion
- standardization
- deduplication
- CDC merge
- business validation
- null handling
- timestamp normalization
- PII handling


## Gold

Purpose:

Produce business-ready datasets.

Examples:

- dim_customer
- dim_policy
- dim_product
- fact_claim
- fact_payment
- customer_360
- claim_daily_summary
- policy_performance
- claim_risk

Gold data should support:

- Athena
- QuickSight
- SageMaker
- downstream AI workloads

---

# 8. Data Sources

Initial business entities:

- customer
- policy
- product
- claim
- payment


## Batch Source

Example:

broker claim CSV files


## OLTP Source

PostgreSQL tables:

- customers
- policies
- products
- claims
- payments


## Streaming Source

Example event types:

- QUOTE_CREATED
- POLICY_VIEWED
- CLAIM_SUBMITTED
- LOGIN
- PAYMENT_ATTEMPT

Every streaming event must contain:

- event_id
- event_type
- event_timestamp
- source
- relevant business identifiers

---

# 9. Production Engineering Requirements

Every production pipeline must consider:

- idempotency
- retry
- failure handling
- logging
- monitoring
- alerting
- data quality
- schema validation
- deduplication
- quarantine
- replay
- auditability
- lineage
- reconciliation
- security

A pipeline is NOT considered complete simply because data reaches the destination.

---

# 10. Retry Strategy

Transient failures should use bounded retries.

Default pattern:

Attempt 1
↓
Retry
↓
Attempt 2
↓
Retry
↓
Attempt 3
↓
Failure Handling

Use exponential backoff where appropriate.

Retries must NOT create duplicate data.

After retry exhaustion:

- mark execution failed
- capture error information
- publish monitoring metrics
- trigger an alert when appropriate

---

# 11. Idempotency

Pipeline reruns must not corrupt data or create unintended duplicates.

The following scenarios must be tested:

- same CSV processed twice
- same event received twice
- same CDC event processed twice
- Step Functions execution retried
- Glue job restarted

Where appropriate use:

- business keys
- event IDs
- file identifiers
- MERGE
- checkpointing
- processing metadata

---

# 12. Data Quality

Data quality is a pipeline gate.

Example rules:

Claim:

- claim_id must not be null
- claim_id must be unique where applicable
- claim_amount >= 0
- valid claim_status
- customer_id must exist
- policy_id must exist

Policy:

- policy_id must not be null
- premium >= 0
- start_date < end_date
- customer_id must exist

Customer:

- customer_id must not be null
- customer_id must be unique
- date_of_birth must be valid

Failed data must not silently continue through the pipeline.

Depending on severity:

FAIL
→ Quarantine
→ Log
→ Alert
→ Stop or isolate processing

---

# 13. Quarantine

Invalid data must be retained for investigation.

Example structure:

quarantine/
    schema_errors/
    data_quality/
    duplicates/
    parsing_errors/

Quarantined data should contain sufficient metadata to determine:

- source
- failure reason
- processing time
- run ID
- original record or file

Never silently delete invalid production data.

---

# 14. Audit Metadata

Every important pipeline execution should have a run_id.

Where applicable capture:

- run_id
- pipeline_name
- source
- stage
- status
- start_time
- end_time
- input_count
- output_count
- rejected_count
- duplicate_count
- quality_score
- error_message

Row-count reconciliation should be implemented where meaningful.

Example:

input_count
=
output_count
+
rejected_count

with documented exceptions where necessary.

---

# 15. Security Requirements

Follow least privilege.

Required principles:

- IAM least privilege
- S3 Block Public Access
- encryption at rest
- encryption in transit
- KMS where appropriate
- secrets stored in Secrets Manager
- no credentials in source code
- no credentials committed to Git
- CloudTrail auditing
- controlled network access
- Lake Formation governance

PII fields may include:

- customer name
- email
- phone
- address
- date of birth

Access to PII must be controlled.

Never log secrets or unnecessary PII.

---

# 16. Terraform Rules

All persistent AWS infrastructure must be defined through Terraform.

Do NOT manually create persistent AWS resources unless explicitly approved for temporary investigation.

Terraform structure should use reusable modules.

Target structure:

terraform/
    bootstrap/
    modules/
    environments/
        dev/
        prod/

Example modules:

- s3
- iam
- kms
- networking
- rds
- dms
- kinesis
- glue
- lakeformation
- step-functions
- monitoring
- sagemaker
- bedrock

Terraform state must use a secure remote backend.

DEV and PROD state must be separated.

Terraform changes must pass:

terraform fmt
terraform validate

and where configured:

tflint
checkov

before merge.

---

# 17. Environment Strategy

Initial environments:

DEV
PROD

Most implementation and testing occurs in DEV.

PROD changes require Human Owner approval.

Resources must use environment-aware naming.

Example:

insurance-dev-data

insurance-prod-data

Avoid hard-coded environment names inside reusable modules.

---

# 18. CI/CD Requirements

Pull Request validation should include:

PR
↓
format
↓
static checks
↓
unit tests
↓
security checks
↓
terraform validate
↓
terraform plan

Deployment:

main
↓
CodePipeline
↓
CodeBuild
↓
DEV deployment
↓
integration tests

Production:

terraform plan
↓
review
↓
Human Approval
↓
terraform apply

Production deployment must NOT happen automatically without approval.

---

# 19. Testing Strategy

Testing should include:

## Unit Tests

Test:

- transformations
- validation logic
- business rules
- utility functions


## Data Quality Tests

Test:

- null constraints
- uniqueness
- ranges
- relationships
- allowed values


## Integration Tests

Test service boundaries.

Examples:

S3 → Glue

DMS → S3

Glue → Iceberg

Gold → Athena


## End-to-End Tests

Example:

Create or modify claim in PostgreSQL
↓
DMS CDC
↓
Bronze
↓
Silver
↓
Gold
↓
Athena validation


## Failure Tests

Intentionally test:

- invalid schema
- duplicate file
- duplicate event
- negative claim amount
- Glue failure
- retry exhaustion
- malformed streaming event

---

# 20. Machine Learning Rules

Initial ML use case:

Claim Fraud Prediction

Preferred initial model:

XGBoost

Use SageMaker.

Pipeline should include:

Gold/Silver Data
↓
Feature Engineering
↓
Train / Validation / Test
↓
Training
↓
Evaluation
↓
Model Artifact
↓
Model Registry
↓
Batch Inference

Avoid persistent real-time endpoints unless required.

Prediction output should include:

- claim_id
- fraud_probability
- risk_level
- model_version
- prediction_timestamp

ML outputs should be reusable by BI where appropriate.

---

# 21. RAG Rules

Initial RAG sources may include:

- insurance policy documents
- claim handling guides
- product documentation
- FAQ
- underwriting guidance

Preferred architecture:

S3 Documents
↓
Bedrock Knowledge Bases
↓
S3 Vectors
↓
Amazon Bedrock

RAG responses must support source attribution/citations.

The first version should remain simple.

Do NOT build complex agentic workflows unless approved.

Do NOT introduce OpenSearch unless justified and approved.

---

# 22. Worker Task Contract

The Manager must give workers clearly scoped tasks.

Every worker task should contain:

TASK ID

OWNER

OBJECTIVE

CONTEXT

INPUTS

OUTPUTS

FILES ALLOWED TO MODIFY

FILES NOT ALLOWED TO MODIFY

DEPENDENCIES

ACCEPTANCE CRITERIA

TESTS REQUIRED

RETURN FORMAT


Example:

TASK-DE-014

Owner:
Data Engineering Worker

Objective:
Implement Silver Claim transformation.

Input:
bronze.claim

Output:
silver.claim

Requirements:

- deduplicate claim_id
- standardize timestamps
- validate claim_amount
- apply CDC semantics
- add run_id
- add etl_timestamp
- add source_system

Files Allowed:

src/silver/claim.py
tests/unit/test_claim.py

Acceptance Criteria:

- unit tests pass
- transformation is idempotent
- duplicate input does not create duplicate output
- data quality rules pass

Return:

- files changed
- implementation summary
- tests executed
- test results
- known risks
- assumptions

---

# 23. Worker Restrictions

Workers must follow the approved architecture.

Workers must NOT independently:

- introduce new AWS services
- change architecture
- change data contracts
- change security architecture
- change Terraform backend strategy
- change CI/CD strategy
- modify another worker's domain without permission
- deploy production infrastructure
- approve their own architectural changes

If a worker believes an architectural change is required, stop implementation and return:

ARCHITECTURE_DECISION_REQUIRED

Include:

- current problem
- proposed change
- reason
- alternatives
- cost impact
- security impact
- affected components

The Manager reviews the proposal.

Major changes require Human Owner approval.

---

# 24. Manager Review Requirements

The Manager must review worker output before considering a task complete.

Review should consider:

- correctness
- architecture compliance
- maintainability
- security
- cost
- testing
- observability
- idempotency
- failure handling
- documentation

The Manager may return work to the worker when requirements are not satisfied.

Workers should fix their own implementation defects when practical.

---

# 25. Human Approval Gates

The Manager MUST stop and report to the Human Owner at the following gates.


## Gate 1 — Architecture Approval

Before infrastructure implementation.

Report:

- architecture
- AWS services
- data model
- data flow
- security approach
- cost approach
- implementation phases
- major risks

Wait for:

APPROVED


## Gate 2 — Core Infrastructure Ready

Report:

- Terraform foundation
- AWS resources
- IAM/security
- estimated cost
- terraform plan summary
- known issues

Wait for approval before major next-stage deployment.


## Gate 3 — Core Data Platform Ready

Report:

- CSV ingestion
- OLTP ingestion
- CDC
- streaming ingestion
- Bronze
- Silver
- Gold
- data quality
- retry
- quarantine
- monitoring
- test results


## Gate 4 — BI / ML / RAG Ready

Report:

- BI status
- ML metrics
- RAG evaluation
- integration status
- cost impact
- known limitations


## Gate 5 — Production Readiness

Report:

- architecture review
- security review
- data quality review
- monitoring review
- testing results
- CI/CD status
- disaster/failure testing
- cost review
- unresolved risks


## Gate 6 — Production Deployment

Before any PROD deployment:

STOP.

Provide:

- Terraform plan summary
- resources created/changed/destroyed
- expected cost impact
- risks
- rollback strategy

Wait for explicit Human Owner approval.

---

# 26. Architecture Decision Records

Important architectural decisions should be documented under:

architecture/adr/

Examples:

ADR-001-use-iceberg.md

ADR-002-use-step-functions.md

ADR-003-athena-instead-of-redshift.md

ADR-004-s3-vectors-for-rag.md

ADR-005-batch-inference.md

Each ADR should contain:

- Context
- Decision
- Alternatives
- Reason
- Cost Impact
- Consequences

---

# 27. Documentation Requirements

Important components should be documented.

Expected documentation includes:

architecture/
    architecture.md
    service-decisions.md
    data-flow.md
    data-contracts.md
    adr/

docs/
    naming-standard.md
    development-standard.md
    cost-principles.md
    runbook.md
    data-dictionary.md
    production-readiness.md

README.md should eventually explain:

- business scenario
- architecture
- AWS services
- setup
- deployment
- pipeline execution
- BI
- ML
- RAG
- testing
- monitoring
- cleanup

---

# 28. Definition of Done

A feature is not complete because the code exists.

A feature is DONE only when applicable requirements are satisfied:

- implementation complete
- tests pass
- architecture followed
- Terraform updated
- data quality implemented
- logging implemented
- failure handling implemented
- retries implemented
- monitoring implemented
- security considered
- cost considered
- documentation updated
- Manager review completed

---

# 29. Current Project Phase

CURRENT PHASE:

PHASE 0 — ARCHITECTURE AND PROJECT FOUNDATION

Implementation must NOT begin yet.

The Manager should first prepare:

1. architecture/architecture.md
2. architecture/service-decisions.md
3. architecture/data-flow.md
4. architecture/data-contracts.md
5. docs/naming-standard.md
6. docs/development-standard.md
7. docs/cost-principles.md
8. initial README.md
9. initial implementation roadmap

The Manager must review these documents for consistency.

After completing Phase 0:

STOP.

Do NOT create AWS resources.

Do NOT start Terraform implementation.

Do NOT start worker implementation.

Present the Gate 1 Architecture Review to the Human Owner.

Wait for explicit approval before continuing.

---

# 30. Guiding Principle

Build the smallest architecture that demonstrates production-quality engineering.

Prefer simplicity over unnecessary complexity.

Prefer AWS-native managed services over custom infrastructure.

Prefer serverless and on-demand services where practical.

Production-quality engineering does not mean production-scale spending.

Every component should have a clear business or engineering reason to exist.