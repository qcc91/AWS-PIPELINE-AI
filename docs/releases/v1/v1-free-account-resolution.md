# V1 FREE account blocker resolution

## Constraint

The Human Owner requires account `199476069493` to remain on the AWS `FREE`
plan. Do not call `freetier upgrade-account-plan`, subscribe to QuickSight or
third-party Marketplace models, or create continuously billed resources only
to probe availability.

## Streaming — ACCOUNT_PLAN_BLOCKED

In `ap-southeast-2`, both Kinesis `ListStreams` and Firehose
`ListDeliveryStreams` return `SubscriptionRequiredException: The AWS Access Key
Id needs a subscription for the service`. AWS lists Kinesis Data Streams and
Amazon Data Firehose as Paid Plan services. Service Quotas, IAM, Organizations
service access, region opt-in, and advanced-account features cannot enable a
service excluded by the account plan.

The V1 runtime proof is therefore `ACCOUNT_PLAN_BLOCKED`. Preserve the approved
Python Producer -> Kinesis -> Firehose -> S3 -> Lakehouse architecture and its
four unapplied Terraform resources without retrying while the account remains
FREE.

## ML — quota requests submitted

The V1 XGBoost pipeline needs one `ml.m5.large` on-demand Training instance and
one `ml.m5.large` Batch Transform instance. All discovered Sydney on-demand
Training and Transform instance quotas were zero, so no suitable low-cost
alternative exists.

| Use | Quota | Code | Current | Requested | Request ID |
|---|---|---|---:|---:|---|
| Training | `ml.m5.large for training job usage` | `L-611FA074` | 0 | 1 | `b519d760dde9440687b17fbd2080ff62OTPDTvP7` / case `178899797700557` |
| Batch Transform | `ml.m5.large for transform job usage` | `L-236AE59F` | 0 | 1 | `3b77277e7eba45ca8519f986852b485dtx2kZBLr` / case `178899780000820` |

The requests were submitted on 2026-09-10 and both reached `CASE_OPENED`. They
create no SageMaker compute or persistent endpoint. Do not start the pipeline
until both applied quotas equal at least one.

## RAG — RESOLVED and V1 COMPLETE

The Human Owner submitted Basic Support case `178899964200695` on 2026-09-10.
AWS investigated the account backend and confirmed that Titan Text Embeddings
V2 has actual limits of 6,000 on-demand requests per minute and 300,000 tokens
per minute in `ap-southeast-2`. The zero shown in Service Quotas is a known
display inconsistency and must not be interpreted as the applied backend quota.

The previous Knowledge Base HTTP 429 responses were genuine throttling during
managed ingestion, not evidence of a FREE-account entitlement block. No quota
increase was requested. After confirming no active ingestion, one
non-overlapping job (`U0DDU3DXFT`) completed in about four seconds, indexed both
documents with zero failures, and created two vectors. Retrieval plus three
Nova Micro grounded-answer checks returned relevant S3 citations. The account
remained FREE; no Marketplace, Support-plan, region, model, or architecture
change occurred.

The historical request below is retained as audit evidence of the original
diagnosis. Its statements that the effective quotas were zero were superseded
by AWS Support's backend investigation.

### Prepared Basic Support request

Subject:

`Amazon Bedrock Titan Text Embeddings V2 has zero applied quota on FREE account in ap-southeast-2`

Body:

> Keep account 199476069493 on the AWS FREE plan; do not convert it to PAID.
> In ap-southeast-2, Knowledge Base AIKVWGQ7FK and data source ZQZTSRBX9Z use
> amazon.titan-embed-text-v2:0. Model availability reports AVAILABLE,
> AUTHORIZED, entitled, and region available, but the account-applied quotas
> are zero and non-adjustable: on-demand requests per minute L-26C560CE=0 and
> tokens per minute L-DE641971=0. StartIngestionJob consistently fails because
> the nested BedrockRuntime InvokeModel returns HTTP 429 Too many requests.
> Request IDs include 205c36a6-611e-47ed-99d4-1bc968c214d2,
> 09827815-bff4-4d4b-a05f-67599d996e3d,
> b7e9c33d-b652-4820-964e-a0a16dd9f65b, and
> 1714f496-2b47-439c-a522-3cec24366fc0. Please confirm whether AWS can assign
> the minimum non-zero Titan embedding on-demand quota for this FREE account
> without a plan upgrade. If not, state the exact eligibility blocker and any
> supported FREE-plan embedding alternative. We will not subscribe to
> Marketplace models, purchase a Support plan, upgrade the account, or retry
> ingestion until advised.

## Cost boundary

This resolution package creates no compute. Existing estimated fixed cost is
USD 76.89/month before usage. RDS, DMS, and the two-AZ Secrets Manager interface
endpoint continue to accrue cost while idle. No cost-optimization destroy/stop
operation is authorized by this package.
