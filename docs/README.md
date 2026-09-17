# 项目文档导航

当前平台已验收并发布为 **v5.0-production-ready**。仓库正在进行纯结构重构；
业务逻辑、AWS 架构、运行语义和 V1–V5 标签均不变。优先阅读当前架构与
运行手册，再按版本查阅历史证据。阶段文档中的“下一步”“待批准”只表示当时
状态，不覆盖最终发布结论。

## 当前架构

- [最终架构](architecture/final-architecture.md)
- [结构化数据流](architecture/data-flow.md)
- [CI/CD 与安全角色](architecture/cicd-security.md)
- [V1–V5 演进](architecture/evolution.md)
- [数据模型](architecture/data-model.md)
- [数据契约](architecture/data-contracts.md)
- [数据字典](architecture/data-dictionary.md)
- [服务决策](architecture/service-decisions.md)
- [ADR 目录](architecture/adr/)

## 运维与开发

- [数据管道运行手册](operations/runbooks/data-pipeline-operations.md)
- [ML/RAG 运行手册](operations/runbooks/ml-rag-operations.md)
- [监控与 CI/CD 运行手册](operations/runbooks/monitoring-cicd-operations.md)
- [Terraform bootstrap](operations/terraform/bootstrap.md)
- [Terraform 开发说明](operations/terraform/development.md)
- [开发标准](operations/development-standard.md)
- [命名标准](operations/naming-standard.md)
- [成本原则](operations/cost-principles.md)

## 安全与治理

- [安全治理](security/security-governance.md)
- [数据治理与 PII](security/data-governance.md)
- [AI 安全边界](security/ai-security.md)
- [DEV 身份 bootstrap 要求](security/dev-identity-bootstrap-requirements.md)

## 已验收版本证据

| 版本 | 完成证据 | 重点补充 |
|---|---|---|
| V1 | [综合验收](releases/v1/v1-completion-review.md) | [Batch](releases/v1/v1-batch-result.md)、[CDC](releases/v1/v1-cdc.md)、[文件扩展](releases/v1/v1-file-source-expansion.md)、[ML](releases/v1/v1-ml-result.md)、[RAG](releases/v1/v1-rag.md) |
| V2 | [可靠性与 DQ 验收](releases/v2/v2-completion-review.md) | [数据语义](releases/v2/v2-data-reliability.md)、[AI 可靠性](releases/v2/v2-ai-reliability.md)、[Streaming 退役 ADR](architecture/adr/ADR-006-retire-streaming.md) |
| V3 | [安全治理验收](releases/v3/v3-completion-review.md) | [数据/PII](security/data-governance.md)、[AI 安全](security/ai-security.md) |
| V4 | [PR CI](releases/v4/v4-github-ci.md)、[最小 CD](releases/v4/v4b-minimal-cd.md) | 精确发布证据保存在 annotated tag `v4.0-cicd` |
| V5 | [验收与发布](releases/v5/v5-completion-review.md) | [运行证据](releases/v5/v5-runtime-evidence.md)、[演练](releases/v5/v5-operational-drill.md)、[AI 回归边界](releases/v5/v5-ai-operational-regression.md) |

[版本路线图](releases/version-roadmap.md)汇总最终交付范围。

## 历史设计

- [初始总体设计](historical/architecture/initial-architecture.md)
- [初始数据流](historical/architecture/initial-data-flow.md)
- [初始实施路线图](historical/plans/implementation-roadmap.md)
- [Phase 1 执行计划](historical/plans/phase-1-execution-plan.md)

这些文件保留早期目标和决策轨迹。部分逻辑实体、Processing/Registry、灾备、
Streaming 和完整 PROD 是历史目标或边界，不能据此推断已部署。实际交付以当前图、
实现和相应验收证据为准。

## 仓库与 Agent 治理

- [仓库结构与历史边界](repository-guide.md)
- [Canonical Agent 宪章](../agents/AGENTS.md)
- [Manager 当前状态](../agents/state/manager/current-phase.md)
