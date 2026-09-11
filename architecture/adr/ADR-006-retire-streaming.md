# ADR-006：V2 起退出 Streaming

## Context

V1 目标架构包含 Kinesis Data Streams 与 Amazon Data Firehose，但当前 AWS `FREE` account plan 对两个服务均返回 `SubscriptionRequiredException`。Human Owner 不希望仅为演示 Streaming 升级账户或增加持续费用。

## Decision

自 V2 起，Streaming 从项目的活动范围和 AWS/Terraform 实现中退出。结构化数据仅保留 Batch/File 与 PostgreSQL full load + CDC，两种入口共同写入一个 Bronze/Silver/Gold Iceberg Lakehouse。不会引入 Kafka、MSK、SQS/Lambda 伪流式、外部平台或其他替代流技术。V1 Git 历史及 `v1.0-happy-path` 标签保持不变，继续如实记录当时的 `ACCOUNT_PLAN_BLOCKED` 状态。

## Alternatives

- 将账号升级为 PAID 后继续 Kinesis/Firehose：因成本与账户约束被 Human 拒绝。
- 替换为其他流技术：会改变已批准架构并偏离小型作品集目标，拒绝。
- 仅保留未部署代码：会使活动架构与可运行范围不一致，拒绝。

## Reason

该项目的核心学习目标可由文件批处理和真实 PostgreSQL CDC 展示。主动缩小范围比保留无法执行的分支更准确、更便宜，也减少维护和误导。

## Cost Impact

移除未使用的 Streaming 编排、Glue、IAM 和日志资源不会增加固定月费，并消除未来单 Kinesis shard 约 USD 13.43/月及 Firehose 用量费用的可能性。

## Consequences

- 不再提供流式延迟、分片、Firehose 缓冲或事件重放演示。
- interaction/event 业务概念仅在能通过 Batch 或 CDC 合理表达时保留。
- Batch 与 CDC 的幂等、DQ、隔离、审计、对账和恢复成为 V2 可靠性证明重点。
