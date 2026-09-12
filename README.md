# AWS Insurance Data & AI Platform

本仓库实现一个面向小数据量、强调工程质量与成本控制的 AWS 保险数据与 AI 平台。V1 Happy Path 已完成并以 `v1.0-happy-path` 固化；V2 Reliability + Data Quality 也已验收，并以 `v2.0-reliable` 固化在提交 `40855ff589314231c257a0b4441929178eea3b0b`。

## 业务场景

平台保留两种结构化数据入口：经纪人理赔与主数据 CSV，以及 Amazon RDS for PostgreSQL 经 AWS DMS 输出的全量与 CDC 数据。两者共同进入同一个 S3 + Apache Iceberg Medallion Lakehouse；RAG 使用独立的文档型路径。Streaming 自 V2 起已按 Human 决策退役，未引入替代流式技术。

当前已验证的下游能力包括：

- Athena 查询 Gold Iceberg；QuickSight 因账号未订阅而保持关闭；
- SageMaker XGBoost 理赔风险批量训练与推理，无持久端点；
- Bedrock Knowledge Bases + S3 Vectors 的可引用 RAG。

核心业务实体为 `customer`、`policy`、`product`、`claim`、`payment`。平台以可重放、幂等、数据质量门禁、隔离、对账、审计、加密、监控和成本控制为主要工程目标。V3 Security + Governance 已获授权，当前正在落实最小权限、PII 分类和 Lake Formation 治理。

## 当前架构

```text
Batch / Files ──────> S3 Landing ─┐
RDS PostgreSQL ─DMS─> S3 Landing ─┴─> EventBridge / Step Functions
                                      └─> Glue Bronze
                                           └─> Glue Silver
                                                ├─> 行级校验 / Quarantine
                                                └─> Glue Data Quality / DQDL
                                                     └─> Glue Gold
                                                          ├─> Athena / BI
                                                          └─> SageMaker batch ML

每个阶段 ─> S3 控制记录、对账、失败审计与可重放身份

Documents ─> S3 ─> Bedrock KB ─> Titan Embeddings V2 ─> S3 Vectors
                                                    └─> Nova Micro 引用式回答
```

Batch 与 CDC 均采用串行 Bronze/Silver/Gold 阶段边界及有界重试。Glue Data Quality 以内联 DQDL 方式运行在行级隔离之后、可信 Silver 写入之前；失败会阻止 Silver/Gold 更新，不使用独立调度或持续计算。

## V1 / V2 实际状态

- V1：Batch、RDS/DMS CDC、Bronze/Silver/Gold Iceberg、Athena、SageMaker XGBoost 批量 ML，以及 Bedrock KB + S3 Vectors RAG 已在 DEV 完成真实 AWS 验证。
- BI：Athena 可用；QuickSight 未订阅，未创建仪表板或付费订阅。
- V2：完成阶段边界、有界重试、内容幂等、重复处理、隔离、运行审计、对账、失败恢复，以及 Batch、CDC、ML、RAG 的可靠性验证。
- Glue Data Quality amendment：真实 FAIL 得分 `0.75` 并阻止可信层变化，真实 PASS 得分 `1.0` 并完成 Gold；集成聚焦测试为 `82 passed`。
- Streaming：V2 已移除相关 Terraform、编排、作业与 AWS 资源，且 Terraform 刷新计划无漂移。
- 环境：仅 DEV 已部署；PROD 只有独立环境与状态设计，未经批准不得部署。

验收证据、运行 ID、Athena 查询 ID、成本与已知限制见 [V2 综合完成报告](docs/v2-completion-review.md)。

## 文档入口

- [总体架构](architecture/architecture.md)
- [服务决策](architecture/service-decisions.md)
- [数据流](architecture/data-flow.md)
- [数据契约](architecture/data-contracts.md)
- [BI 与 ML 共享数据模型](architecture/data-model.md)
- [数据字典](docs/data-dictionary.md)
- [V2 数据可靠性与 Glue Data Quality](docs/v2-data-reliability.md)
- [V2 AI 可靠性](docs/v2-ai-reliability.md)
- [V2 基础设施变更](docs/v2-infrastructure.md)
- [V2 综合完成报告](docs/v2-completion-review.md)
- [V3 安全与治理清单](docs/security-governance.md)
- [V3 数据治理与 PII 设计](docs/v3-data-governance.md)
- [V3 ML/RAG 安全边界](docs/v3-ai-security.md)
- [V1–V5 累计版本路线图](docs/version-roadmap.md)
- [退役 Streaming 的 ADR](architecture/adr/ADR-006-retire-streaming.md)

## 仓库结构

```text
architecture/    架构、数据流、数据契约与 ADR
docs/            版本结果、运行说明、成本与工程文档
terraform/       bootstrap、可复用模块及 DEV/PROD 环境
jobs/            Glue 作业脚本
src/             Batch、CDC、可靠性、BI、ML 与 RAG 代码
tests/           基础设施、数据、ML 与 RAG 测试
sample-data/     非敏感合成样例数据
scripts/         部署辅助与运行验证脚本
agent-state/     Manager 与 Worker 的持久状态
```

## 本地验证

离线基础设施检查不会调用 AWS、不会执行 `terraform apply`，可在 PowerShell 中运行：

```powershell
./tests/infrastructure/validate.ps1
```

已初始化 Terraform provider 的环境可另外执行：

```powershell
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev validate
```

数据、ML 与 RAG 的聚焦测试位于 `tests/data`、`tests/ml` 和 `tests/rag`。真实 AWS 重放和验收步骤应按对应的 V1/V2 文档执行；任何资源变更仍受 Human package-level approval 与 `AGENTS.md` 约束。

## 环境与交付原则

- 默认 Region 为 `ap-southeast-2`（Sydney），不得静默跨区。
- DEV 是实际实施环境；PROD 必须保持隔离并在部署前获得明确批准。
- 持久 AWS 基础设施通过 Terraform 管理，不提交状态、plan、凭据、token、`.tfvars` 或本地环境文件。
- 优先使用 serverless、on-demand、短时批处理和小规格资源，不为假设规模预置容量。
- AWS 账号保持 FREE plan；不自动订阅 QuickSight、Marketplace 或升级账号套餐。
- V3 安全治理已授权；非 root IAM 用户及 Operator → TerraformExecution 角色入口已创建，当前等待人工设置控制台密码并绑定 MFA。V4 CI/CD 与 V5 生产就绪尚未开始。
