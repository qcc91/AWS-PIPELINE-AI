# AWS Insurance Data & AI Platform

本仓库用于设计并逐步实现一个低数据量、生产工程质量、成本受控的 AWS 保险数据与 AI 平台。Gate 1 已于 2026-09-08 获 Human Owner 批准；当前只授权 **V1 end-to-end happy path**。Terraform 基础代码已存在并进入真实 plan 准备，但尚未创建任何 AWS 资源，业务流水线也尚未实现。

## 业务场景

平台统一接入三类数据：经纪人理赔 CSV、Amazon RDS for PostgreSQL 的 OLTP 全量与 CDC、以及保单/理赔/登录/支付等流事件。Landing 保留原始对象，Bronze、Silver、Gold 全部采用 S3 上的 Apache Iceberg，形成可治理的 Lakehouse，并向三个方向复用：

- Athena / QuickSight 分析；
- SageMaker 理赔欺诈批量训练与推理；
- Bedrock Knowledge Bases + S3 Vectors 的可引用 RAG。

核心实体为 `customer`、`policy`、`product`、`claim`、`payment`。平台的首要非功能要求是可重放、幂等、数据质量门禁、隔离、对账、审计、最小权限、加密、监控和成本控制。

## 目标架构

```text
CSV ────────────────> S3 Landing ─┐
RDS PostgreSQL ─DMS─> S3 Landing ─┼─> Glue ─> Bronze/Silver/Gold Iceberg
Events ─Kinesis─Firehose─> S3 ────┘                         │
                                                            ├─> Athena/QuickSight
Documents ─> S3 ─> Bedrock KB ─> S3 Vectors                 ├─> SageMaker batch ML
                                                            └─> governed consumers
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
- 所有持久 AWS 基础设施最终必须由 Terraform 管理；Phase 0 不实施 Terraform。
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

Phase 0、Gate 1 和基础设施实施计划已完成审批。当前继续 V1
基础设施 plan 准备；任何 `terraform apply` 必须先经过 Human 对真实 plan
的明确批准。V2–V5 仅作为路线图，不在当前授权范围内。

后续阶段的安装、部署、运行、BI、ML、RAG、测试、监控和清理命令将在对应实现完成且通过审批后补充，当前不提供不可执行的占位命令。
