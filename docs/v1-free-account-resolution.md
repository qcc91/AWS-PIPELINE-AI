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

## RAG — no currently usable FREE-compatible embedding model

Live Sydney discovery produced the following result:

| Candidate | Account/model state | Effective RPM | Knowledge Base decision |
|---|---|---:|---|
| `amazon.titan-embed-text-v2:0` | available, authorized, entitled | `L-26C560CE=0`, non-adjustable | Correct existing text model, but blocked |
| `amazon.titan-embed-image-v1` | available, authorized, entitled | `L-DF0E34D4=0`, non-adjustable | Multimodal path needs a new KB/content configuration; not a minimal text substitute |
| `cohere.embed-english-v3` | authorized/region available, agreement unavailable | `L-FF8E7864=0`, non-adjustable | Third-party Marketplace agreement; do not subscribe |
| `cohere.embed-multilingual-v3` | authorized/region available, agreement unavailable | `L-9E5BD0C6=0`, non-adjustable | Third-party Marketplace agreement; do not subscribe |
| `cohere.embed-v4:0` | inference-profile only; agreement unavailable | no usable in-region quota | Cross-region/Marketplace and not the approved self-managed path |

No model invocation was sent for candidates whose effective RPM is already
zero or whose Marketplace agreement is unavailable. This avoids deterministic
throttling and unintended third-party subscription. The existing Titan V2
failure is Bedrock Agent `StartIngestionJob` `ValidationException` wrapping a
BedrockRuntime HTTP 429 `Too many requests`; it is quota, not IAM/model access.

The Titan quota is not adjustable through Service Quotas. With the account kept
FREE, the remaining official route is an AWS Support account/quota review. A
Basic Support case must request investigation of why the applied, non-adjustable
Titan Text Embeddings V2 on-demand RPM quota is zero despite the model being
authorized and available in Sydney. Include account, region, model ID, quota
code, Knowledge Base/data source IDs, error text, and the recorded request IDs.
Do not purchase a Support plan; if AWS will not accept the case under Basic
Support, leave RAG `ACCOUNT_QUOTA_BLOCKED`.

On 2026-09-10, the authenticated account called the read-only AWS Support
`DescribeServices` operation to determine whether automatic case submission was
available. AWS returned `SubscriptionRequiredException: Amazon Web Services
Premium Support Subscription is required to use this service`. The Support API
therefore cannot submit this Basic Support case. Console submission is required;
do not upgrade the Support plan.

The Human Owner submitted the prepared request through the Basic Support
console on 2026-09-10. Case ID `178899964200695` was created at
`2026-09-10T00:20:42.712Z`; its initial status is `Unassigned`, severity is
`General question`, and category is `Service Quotas, General`. Do not retry
Titan while the case is unresolved and effective RPM remains zero.

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
