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

The platform supports two active structured ingestion patterns:

1. Batch CSV files
2. PostgreSQL OLTP database with CDC

Streaming was part of V1 but is intentionally retired from V2 onward by Human
decision. Do not introduce a replacement streaming technology.

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


## Retired Streaming Source

Kinesis Data Streams and Data Firehose are not part of the active architecture
from V2 onward. Useful event-shaped business data may enter through Batch or CDC,
but no substitute streaming architecture may be introduced.

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

---

# 20. Machine Learning Rules

Initial ML use case:

Claim Risk Prediction at claim-submission time

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
- high_risk_probability
- risk_level
- model_version
- prediction_timestamp

The V1 target is `high_risk_claim`, derived from future synthetic severity or
high-cost outcome. Prediction-time features must use only information available
at or before claim submission. Approved/paid amounts, final status/severity,
investigation results, settlement duration, and other post-submission outcomes
must not enter the feature matrix.

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

# 22. Worker Work-Package Contract

The Manager must give workers clearly scoped, end-to-end engineering work packages.
For this learning/portfolio project, prefer one complete package over a sequence
of micro-tasks. A package includes implementation, tests, routine debugging,
and a single consolidated Worker return.

Every worker package should contain:

PACKAGE ID

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

The Manager must review worker output before considering a package complete.
The Manager performs one consolidated package review and handles formatting,
lint, provider download, local syntax, tests, and normal Worker rework
autonomously. These routine issues do not require Human Owner review.

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


## Gate 2 — Terraform Plan Approval

Report:

- trustworthy bootstrap and foundation Terraform plans
- exact create/change/destroy counts
- non-root execution identity and state strategy
- expected AWS resources
- IAM/KMS/Lake Formation impact
- expected monthly cost
- security risks, rollback, and known issues

Wait for explicit approval before any AWS resource-changing operation.


## Gate 3 — Core Data Platform Ready

Report:

- CSV ingestion
- OLTP ingestion
- CDC
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

# 29. Iterative Version Roadmap

The final project requirements and target architecture remain unchanged. The
team designs for V5 but implements only the currently authorized version in one
evolving codebase:

- V1 — End-to-end happy path: functional DEV infrastructure, batch, CDC,
  the historically account-blocked streaming branch, Bronze/Silver/Gold Iceberg, Athena/QuickSight, SageMaker batch ML,
  and Bedrock Knowledge Bases with S3 Vectors.
- V2 — Reliability and data quality: retire Streaming; add stage boundaries,
  retries, idempotency, deduplication, DQ, quarantine, audit metadata,
  reconciliation, and recovery to Batch, CDC, ML, and RAG.
- V3 — Security and governance: least privilege, Lake Formation role/PII
  controls, KMS refinement, Secrets Manager, audit, and security validation.
- V4 — CI/CD and environment automation: independent remote DEV/PROD state,
  GitHub integration, CodePipeline/CodeBuild, automated gates, and tests.
- V5 — Production readiness: complete observability, alerting, failure/replay/
  recovery tests, retention/cost/security review, runbooks, and final E2E proof.

The roadmap is cumulative. Do not build five implementations, remove correct
later-version code merely because it already exists, or prematurely perfect
V2–V5 features during V1.

---

# 30. Current Project Phase

CURRENT PHASE:

V3 — SECURITY + GOVERNANCE

The Human Owner requires this project to remain on the AWS `FREE` account plan.
Never call `aws freetier upgrade-account-plan`, subscribe to QuickSight or a
third-party Marketplace model, or create continuously billed resources only to
probe account capability.

Gate 1 and the Phase 1 execution plan were approved by the Human Owner on 2026-09-08.

The DEV bootstrap, foundation, and V1 Batch happy path have been deployed and
verified after explicit Human plan/apply approvals. The Batch path is complete:
S3 Landing -> EventBridge -> Step Functions -> Glue -> Bronze/Silver/Gold
Iceberg -> Athena.

The CDC package has also completed its real DEV happy path: RDS PostgreSQL ->
DMS full load/CDC -> S3 -> EventBridge -> Step Functions -> Glue ->
Bronze/Silver/Gold Iceberg -> Athena. Athena confirmed the expected insert,
update, and delete results.

The Human-approved `V1 FILE-BASED SOURCE EXPANSION` package completed on
2026-09-10. Deterministic product, broker, branch, claim-type, region-risk,
vehicle, and coverage CSV master/reference sources and an expanded broker claim
feed ran through the existing Landing, EventBridge, Step Functions, Glue,
Bronze/Silver/Gold Iceberg, and Athena path. The package did not modify RDS.
Athena confirmed the expected row counts, zero missing cross-source references,
and zero future-reference use in the point-in-time feature join.

The current OLTP tables do not contain broker, region, coverage, vehicle, or
claim-type transaction foreign keys. The approved V1 file integration extends
the existing external broker-claim Batch feed with those reference keys while
reusing OLTP policy/customer identifiers; product enrichment uses
`policy.product_id -> product_master.product_id`. The file claim source must
not overwrite or be misrepresented as the PostgreSQL claim source of truth.

Athena BI is functional. QuickSight remains disabled because the account is
not subscribed. V1 ML completed on 2026-09-10 after its quotas propagated:
Gold `claim_risk_features` -> one `ml.m5.large` XGBoost Training -> encrypted
model artifact -> one `ml.m5.large` Batch Transform -> Glue -> Gold
`claim_risk` -> Athena. The run produced 120 predictions; validation AUC was
0.65556 and independent Test AUC was 0.62222. No endpoint or notebook was
created, and the transient SageMaker Model was deleted after publication.
- RAG runtime proof is complete. AWS Support case `178899964200695` confirmed that the Service Quotas display
  of zero is a known inconsistency. The actual Titan Text Embeddings V2 backend
  limits are 6,000 RPM and 300,000 TPM. The earlier HTTP 429 responses were
  genuine transient ingestion throttling, not a FREE-plan entitlement block.
  One non-overlapping ingestion job indexed both approved documents with zero
  failures. S3 Vectors retrieval and three Nova Micro grounded answers with S3
  citations passed real AWS validation.

Do not request a Titan quota increase for the small corpus. Streaming is retired,
not blocked or pending activation. Do not restore or replace it.

Historical Phase 1 scope and task contracts are defined in:

docs/phase-1-execution-plan.md

Routine formatting, validation, lint, provider download, local syntax, test
failures, and Worker rework are handled internally without Human checkpoints.
Any AWS-changing operation must remain inside the approved V3 package;
destructive actions, new services, material architecture/security/cost changes,
and all production operations require Human approval.

Do NOT deploy PROD resources.

V1 package execution and its consolidated review are complete and preserved by
tag `v1.0-happy-path` at commit `9d4f625`. V2 Reliability + Data Quality is
accepted and preserved by tag `v2.0-reliable` at commit
`40855ff589314231c257a0b4441929178eea3b0b`. Human authorized V3 on 2026-09-12.
From V2 onward Streaming is intentionally retired: remove its active code,
Terraform, AWS orchestration, tests, docs, and task state without introducing a
replacement. Batch/File and PostgreSQL full-load+CDC are the two structured
ingestion patterns feeding one shared Bronze/Silver/Gold Iceberg Lakehouse.

V3 is limited to security inventory, non-root operator/persona roles, IAM least
privilege, PII classification, Lake Formation governance, S3/KMS/Secrets/
CloudTrail hardening, and real ALLOW/DENY access tests. Human approved Option A:
one console-only IAM user as the authentication entry point, with no access key
or direct project-service permissions. Bootstrap Terraform created that user,
the MFA-protected Operator role, and the distinct TerraformExecution role on
2026-09-12 (`7 add / 0 change / 0 destroy`). The Human Owner must now set the
initial console password and enroll MFA interactively. After that, routine CLI
and Terraform work must use the non-root role chain; root is not a normal
operator. Do not enable Identity Center or create additional IAM users or keys.

V4 CI/CD, V5 production readiness, PROD deployment, QuickSight subscription,
account-plan upgrade, paid security services, and Marketplace purchases remain
out of scope. After V3 implementation, real AWS evidence, documentation, commit,
and push, STOP for Human consolidated review and do not create a V3 release tag.
Each package follows:

Manager scope -> Worker implementation and tests -> one consolidated Manager
review -> internal rework as needed -> meaningful Human gate.

---

# 31. Guiding Principle

Build the smallest architecture that demonstrates production-quality engineering.

Prefer simplicity over unnecessary complexity.

Prefer AWS-native managed services over custom infrastructure.

Prefer serverless and on-demand services where practical.

Production-quality engineering does not mean production-scale spending.

Every component should have a clear business or engineering reason to exist.
