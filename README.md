# AWS-PIPELINE-AI

**COMPLETE — v5.0-production-ready** · AWS Sydney · Terraform · Python · Apache Iceberg

面向保险理赔的 AWS 数据与 AI 工程作品集：将经纪人 CSV、参考数据和 PostgreSQL 变化记录转为可查询、可重放、受治理的数据，支撑批量风险预测与带来源引用的文档问答。

项目通过 Human 决策与验收、Manager AI Agent 协调及专业 Workers 实现，累计交付 V1–V5。关键路径在真实 AWS DEV 环境验证；PROD 仅包含经过人工审批的最小 CI/CD 验证资源。

## What This Project Demonstrates

- **数据工程**：Batch + DMS Full Load/CDC，共享 S3 Bronze/Silver/Gold Iceberg Lakehouse。
- **可靠性与质量**：分阶段 Glue 编排、有界重试、内容幂等、CDC 当前态重建、行级隔离、Glue DQDL 门禁和对账。
- **安全与治理**：MFA 角色链、Lake Formation 数据访问边界、PII 限制、KMS、Secrets Manager、CloudTrail。
- **数据消费**：Athena BI、验收样本范围内时点安全的 XGBoost 批量风险预测、Bedrock Knowledge Bases + S3 Vectors 文档 RAG。
- **交付与运维**：受保护 PR CI、精确二进制计划审批、故障注入、告警、恢复演练及运行手册。

## Final Architecture

[查看最终架构图：数据平台、AI 分支、运维、安全与交付边界](docs/architecture/final-architecture.md)

完整 DEV 平台保留文件和 CDC 两个结构化入口。RAG 独立摄入获批保险文档，不直接读取 Gold 客户数据。Streaming/Kinesis/Firehose 已在 V2 退役；QuickSight 保持未订阅。

## Data Flow

[查看数据流图：Landing → Bronze → DQ → Silver → Gold，以及重放与消费](docs/architecture/data-flow.md)

Batch 以内容摘要识别重复；CDC 保留 I/U/D 和排序信息，从小规模保留历史重建当前态。无效记录隔离后，候选可信数据须通过 DQDL 门禁才写入 Silver。各阶段留下 run ID、计数和对账记录。

## Engineering Evolution

[查看 V1 → V5 演进路线图](docs/architecture/evolution.md)

V1 打通真实路径 → V2 增强可靠性与质量 → V3 收紧安全治理 → V4 自动化交付 → V5 验证可运维性。同一代码库持续演进，发布标签保留各版本证据。

## CI/CD & Security

[查看 CI/CD 与安全角色图](docs/architecture/cicd-security.md)

GitHub Actions 对完整仓库执行格式、Terraform 验证、单元/静态安全测试及高置信度凭据扫描，PR 必需检查保护 main。PR CI 不持有 AWS 凭据；真实 Terraform plan 在 AWS CD 中生成。

main 合并经 CodeConnections 自动触发 CodePipeline/CodeBuild。CD 仅操作独立 DEV/PROD proof stack：每个环境一个 CloudWatch Log Group。PROD 经人工批准后应用同一二进制计划，核对 source SHA、execution ID 和 SHA256，再做资源验证及零漂移检查。人工 MFA 管理路径与机器部署角色分离，无长期 AWS 访问密钥。

## Key Engineering Capabilities

| 领域 | 已实现与验证 | 代码 / 证据 |
|---|---|---|
| Batch / CDC | 三层 Iceberg、I/U/D、重复处理、阶段审计 | [Batch](pipelines/ingestion/batch/) / [CDC](pipelines/ingestion/cdc/)、[数据可靠性](docs/releases/v2/v2-data-reliability.md) |
| 数据质量 | 行级隔离 + 内联 Glue DQDL，真实 FAIL/PASS | [质量控制](pipelines/quality/)、[V2 验收](docs/releases/v2/v2-completion-review.md) |
| 治理 | Analyst/ML/RAG 边界，真实 ALLOW/DENY | [治理模块](infrastructure/terraform/modules/security-governance/)、[V3 验收](docs/releases/v3/v3-completion-review.md) |
| BI | Athena 查询与 Gold 指标；QuickSight 延后 | [BI workload](workloads/bi/)、[BI 说明](docs/releases/v1/v1-bi.md) |
| ML | 120 条、54 维时点特征，Training → Batch Transform → Gold | [当前特征代码](workloads/ml/claim_risk.py)、[真实指标与限制](docs/releases/v1/v1-ml-result.md) |
| RAG | 两份文档、Titan V2、Nova Micro 回答及 S3 引用 | [RAG workload](workloads/rag/)、[真实运行](docs/releases/v1/v1-rag.md) |
| 运维 | 四个告警、Glue/EventBridge/SNS、DMS 失败订阅、恢复重放 | [运行手册](docs/operations/runbooks/)、[V5 证据](docs/releases/v5/v5-runtime-evidence.md) |

V5 验收包含 **115/115 自动化测试**、Batch 重放后 **121/121 唯一理赔**、CDC **10/10 DQ 规则**及 **3/3 唯一 Gold 理赔**。这些是已记录的验收结果，不是实时健康度或生产规模性能承诺。

## AI-Agent Engineering Workflow

Human 定义业务范围、架构、成本与安全约束；Manager AI Agent 拆分工作包、冻结接口并整合审查；Infrastructure、Data Engineering、AI Engineering Workers 完成实现、测试和常规调试。稳定的契约允许下游工作并行推进。

重大架构、安全、成本、破坏性操作与 PROD 变更由 Human 决策。关键功能有真实 AWS 运行证据后才验收。AI 参与实现和排错，Human 保留范围控制与最终接受权。[工程规则](agents/AGENTS.md) · [验收导航](docs/README.md)

## Repository Structure

| 目录 | 用途 |
|---|---|
| [pipelines/](pipelines/) | Batch/CDC ingestion、Bronze/Silver/Gold 职责导航、DQ、隔离、审计和重放 |
| [workloads/](workloads/) | Athena/BI、SageMaker ML、Bedrock/S3 Vectors RAG |
| [infrastructure/](infrastructure/) | Terraform 与 CI/CD 工程；完整平台和 proof roots 保持隔离 |
| [data/](data/) | 可复现的合成源、参考数据和小型验收样本 |
| [tests/](tests/) | 数据、基础设施、安全、ML、RAG 测试 |
| [docs/](docs/) | 当前架构、运维、安全、版本证据和历史设计导航 |
| [agents/](agents/) | AI 工程规范和历史协作状态 |
| [.github/workflows/](.github/workflows/) | GitHub 要求的活动 PR workflow 位置，逻辑上属于 Infrastructure / CI-CD |

历史 claim_fraud 命名与 smoke fixtures 保留兼容性；正式用例是 high_risk_claim，以 [claim_risk.py](workloads/ml/claim_risk.py) 和 [ML 完成报告](docs/releases/v1/v1-ml-result.md) 为准。[仓库审计与历史边界](docs/repository-guide.md)

## Local Checks

在 Python 3.12 和 Terraform 1.16.1 环境中：

```text
python -m pip install -r requirements-ci.txt
python infrastructure/cicd/check_repository_consistency.py
terraform fmt -check -recursive infrastructure/terraform
python -m pytest -q tests/data tests/infrastructure tests/ml tests/rag
```

完整 backend-free 初始化/验证见 [PR CI](.github/workflows/pull-request-ci.yml)。真实操作参照 [数据手册](docs/operations/runbooks/data-pipeline-operations.md)、[ML/RAG 手册](docs/operations/runbooks/ml-rag-operations.md) 和 [交付手册](docs/operations/runbooks/monitoring-cicd-operations.md)。

## Releases

| 发布 | 目标 | 验收证据 |
|---|---|---|
| [v1.0-happy-path](https://github.com/qcc91/AWS-PIPELINE-AI/tree/v1.0-happy-path) | Make it work | [V1](docs/releases/v1/v1-completion-review.md) |
| [v2.0-reliable](https://github.com/qcc91/AWS-PIPELINE-AI/tree/v2.0-reliable) | Make it reliable | [V2 + DQ amendment](docs/releases/v2/v2-completion-review.md) |
| [v3.0-governed](https://github.com/qcc91/AWS-PIPELINE-AI/tree/v3.0-governed) | Make it secure | [V3](docs/releases/v3/v3-completion-review.md) |
| [v4.0-cicd](https://github.com/qcc91/AWS-PIPELINE-AI/tree/v4.0-cicd) | Automate delivery | [V4A](docs/releases/v4/v4-github-ci.md) / [V4B](docs/releases/v4/v4b-minimal-cd.md) |
| [v5.0-production-ready](https://github.com/qcc91/AWS-PIPELINE-AI/tree/v5.0-production-ready) | Make it operable | [V5 与最终发布](docs/releases/v5/v5-completion-review.md) |

## Cost-Aware Design

账号保持 AWS FREE plan；**FREE 不等于资源零成本**。历史 V1 估算约 USD 76.89/月（不含用量），主要来自 RDS、DMS 与私有端点，已单独批准；不是当前账单。V5 新增告警历史估算不超过约 USD 0.60/月，演练 Glue 估算约 USD 0.30，见 [成本证据](docs/releases/v5/v5-completion-review.md)。

采用短时作业、无持久推理端点、无 NAT Gateway、无完整 PROD 副本。QuickSight 未订阅；Streaming 因账户限制经 Human 决策退役。最小 PROD 证明审批与部署机制，不承担业务数据平台负载。

## Known Limitations

- 单账户、合成小数据集；完整 PROD、高可用和跨区域灾备未部署。
- DMS 历史全量/CDC 曾通过；后续任务处于已接受的 failed 状态，V5 证明保留历史重放，不代表持续 CDC 已恢复。
- SNS 发布已验证，尚无 Human 邮件/SMS 订阅；QuickSight 仪表板未部署。
- ML 测试 AUC 0.62222，0.50 阈值下 F1 为 0，全部预测落入 MEDIUM；不能用于真实业务决策。参考特征使用预先日期的单一快照，尚无多版本 as-of join。
- RAG 仅两份文档、三条代表性引用验证，未证明大规模检索质量。
- 全 CI 覆盖仓库；CD 仅覆盖 proof stack。文档或结构变更合并也会触发同一 proof CD，因此仍须停在 PROD 人工审批门。

## Project Status

**COMPLETE — v5.0-production-ready**，发布标签仍指向最终验收提交 `5e0b479fa47130930dd9d4c0b0ad1005244ff335`。后续作品集与目录整理只改善展示和导航，不改变 V1–V5 实现或标签。
