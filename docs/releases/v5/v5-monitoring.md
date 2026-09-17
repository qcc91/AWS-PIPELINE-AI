# V5 focused monitoring and retention

## Scope

V5 reuses the existing encrypted `insurance-dev-critical-alerts` SNS topic and
adds a deliberately small DEV-only signal set. It creates no subscription,
Lambda function, polling service, persistent compute, replacement ingestion
path, or PROD platform resource.

| Signal | Mechanism | Scope |
|---|---|---|
| Batch workflow failure/timeout/abort | CloudWatch metric-math alarm | Exact Batch state machine ARN |
| CDC workflow failure/timeout/abort | CloudWatch metric-math alarm | Exact CDC state machine ARN |
| Glue failed/stopped/timed-out job | EventBridge rule to SNS | Seven existing Batch/CDC/seed jobs |
| DMS task failure | DMS event subscription to SNS | Exact existing replication task ID |
| CodePipeline failure | CloudWatch alarm | `insurance-dev-v4b-cd` |
| CodeBuild failure | One metric-math alarm | Three accepted V4B deployment projects |

The alarms use one evaluation period and `treat_missing_data = notBreaching`.
Metric-math expressions fill absent metrics with zero, so inactive workflows do
not produce false alarms. Every alarm action targets the existing encrypted SNS
topic. The topic policy constrains CloudWatch and DMS publishers by account or
exact source ARN. EventBridge SNS targets do not support policy conditions, so
its service-principal grant is limited to `sns:Publish` on this exact topic; the
exact named Glue rule and narrowly scoped Terraform IAM permission are the
compensating boundary. The audit KMS policy grants only encryption use for
CloudWatch, EventBridge, and DMS against this exact topic encryption context.

The explicit topic policy preserves the standard same-account owner statement
(`AWS:SourceOwner`) before adding the service publishers; it does not replace
the topic's existing owner-management semantics. DMS publishing is further
limited to the exact event-subscription ARN recommended by the AWS DMS guide.

No human SNS endpoint is invented or subscribed. V5 can prove alarm/event
delivery to the topic through CloudWatch alarm history, EventBridge metrics and
CloudTrail/SNS evidence; adding an email/SMS endpoint remains a Human-owned
confirmation action.

## Known monitoring limits

Bedrock Knowledge Base ingestion does not expose a low-cost native CloudWatch
terminal-failure metric suitable for an alarm. Adding a scheduled poller or
Lambda would expand the architecture, so RAG remains covered by ingestion-job
status, CloudTrail and the existing operational regression script. Glue Data
Quality rejection remains quarantine/audit evidence rather than a custom paid
metric. The pre-existing DMS failed state is not repaired by this package; only
future failure events are routed.

## Retention review

No new destructive lifecycle rule is needed:

- application, Glue, Step Functions, ML, CodeBuild, CloudTrail and proof log
  groups: 30 days;
- quarantine current objects: 90 days;
- CloudTrail audit current objects: 365 days;
- V4B plan/artifact current and noncurrent objects: 90 days;
- data bucket noncurrent versions: 30 days.

Landing, lakehouse, control and document current objects remain unexpired.
Consequently the V5 change cannot expire accepted business data.

## IAM boundary

TerraformExecution receives only the APIs needed to manage the named alarms,
one named EventBridge rule, the existing alert-topic policy and one tagged DMS
event subscription. AWS DMS event-subscription IAM actions do not expose a
resource type, so their unavoidable `Resource = "*"` statements are constrained
to Sydney and the project request/resource tags. The permission grants no S3
object, secret, PII or Human identity access. The bootstrap identity remains
separately managed.

The DEV bootstrap root receives the two existing platform/audit KMS key ARNs
as explicit required plan inputs. It no longer reads their aliases. This keeps
bootstrap planning independent of application-key discovery privileges and
does not grant bootstrap management over either application key.

## Cost

There is no new fixed compute or KMS key. Four alarms evaluate ten standard
service metrics in total. Before any applicable CloudWatch free allowance, the
conservative recurring estimate is approximately USD 1/month. SNS, EventBridge
AWS-service events, DMS events and KMS/SNS requests are usage-based and expected
to be negligible for the small DEV workload. There is no SNS subscription
delivery charge while no endpoint exists.
