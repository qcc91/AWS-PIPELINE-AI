# AWS Insurance Data & AI Platform

本仓库实现一个低数据量、生产工程质量、成本受控的 AWS 保险数据与 AI 平台。V1 Happy Path 已完成并以 `v1.0-happy-path` 固化；当前实施 **V2 reliability + data quality**，聚焦幂等、质量门禁、隔离、审计、对账和安全重放。

## 业务场景

平台以两种结构化入口接入数据：经纪人理赔/主参考 CSV，以及 Amazon RDS for PostgreSQL 经 DMS 输出的全量与 CDC。两者共同进入同一个 S3 + Apache Iceberg Medallion Lakehouse；RAG 文档保留独立的文档型路径。V2 起 Streaming 已由 Human 明确退出项目范围，且不引入替代流技术。

- Athena / QuickSight 分析；
- SageMaker 理赔欺诈批量训练与推理；
- Bedrock Knowledge Bases + S3 Vectors 的可引用 RAG。

核心实体为 `customer`、`policy`、`product`、`claim`、`payment`。平台的首要非功能要求是可重放、幂等、数据质量门禁、隔离、对账、审计、最小权限、加密、监控和成本控制。

## 目标架构

```text
Batch / Files ──────> S3 Landing ─┐
RDS PostgreSQL ─DMS─> S3 Landing ─┴─> Step Functions
                                      └─> Glue Bronze ─> Glue Silver ─> Glue Gold
                                                                    ├─> Athena / BI
                                                                    └─> SageMaker batch ML
Documents ─> S3 ─> Bedrock KB ─> Titan Embeddings V2 ─> S3 Vectors ─> cited answers
```

完整边界、数据流和契约见：

- [总体架构](architecture/architecture.md)
- [服务决策](architecture/service-decisions.md)
- [数据流](architecture/data-flow.md)
- [数据契约](architecture/data-contracts.md)
- [BI 与 ML 共享数据模型](architecture/data-model.md)
- [数据字典](docs/data-dictionary.md)
- [实施路线图](docs/implementation-roadmap.md)
- [Phase 1 执行计划](docs/phase-1-execution-plan.md)
- [V1–V5 累计版本路线图](docs/version-roadmap.md)
- [V1 实施计划与现状映射](docs/v1-implementation-plan.md)

## 环境与交付原则

- 环境仅为 `dev` 与 `prod`，配置和状态严格分离。
- 默认 AWS Region 为 `ap-southeast-2`（Sydney）；不得静默跨区。
- DEV 是实际实施主环境；PROD 只设计独立 Terraform environment/state，明确批准前不部署。
- 所有持久 AWS 基础设施由 Terraform 管理；DEV 已部署，PROD 未部署。
- 主分支先部署 DEV 并执行集成测试；PROD 必须经过人工审批。
- 默认选择 serverless、on-demand、batch、小规格和自动清理；不为假设的大规模负载预置容量。
- 禁止在代码、日志、样例数据中放置凭据或不必要的 PII。

## 规划中的仓库结构

```text
architecture/    架构、服务决策、数据流、契约和 ADR
docs/            命名、研发、成本、运行与就绪文档
terraform/       后续阶段的 bootstrap/modules/environments
src/             后续阶段的数据、ML 与 RAG 代码
tests/           后续阶段的单元、集成、端到端和故障测试
sample-data/     后续阶段的非敏感合成样例
```

## 当前状态与下一步

V2 已获 Human package-level 授权并在 DEV 实施；V3 安全治理、V4 CI/CD、V5 生产就绪均未开始。V1 历史证据保留在 `v1.0-happy-path`，V2 不改写该标签。当前运行结果与限制见 `docs/v2-completion-review.md`（完成验证后更新）。
