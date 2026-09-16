# 项目文档导航

当前平台已验收并发布为 **v5.0-production-ready**。先读当前图与运行手册，再按需要查历史证据。版本文档中的“下一步”“待批准”描述属于当时状态，不覆盖最终发布状态。

## 当前架构与操作

- [最终架构](architecture/final-architecture.md)
- [数据流](architecture/data-flow.md)
- [CI/CD 与安全角色](architecture/cicd-security.md)
- [V1–V5 演进](architecture/evolution.md)
- [数据运行手册](runbooks/data-pipeline-operations.md)
- [ML/RAG 运行手册](runbooks/ml-rag-operations.md)
- [监控与 CI/CD 运行手册](runbooks/monitoring-cicd-operations.md)
- [数据字典](data-dictionary.md)、[数据契约](../architecture/data-contracts.md)
- [仓库分类与历史边界](repository-guide.md)

## 已验收的版本证据

| 版本 | 完成证据 | 重点补充 |
|---|---|---|
| V1 | [综合验收](v1-completion-review.md) | [Batch](v1-batch-result.md)、[CDC](v1-cdc.md)、[文件扩展](v1-file-source-expansion.md)、[ML](v1-ml-result.md)、[RAG](v1-rag.md) |
| V2 | [可靠性与 DQ 验收](v2-completion-review.md) | [数据语义](v2-data-reliability.md)、[AI 可靠性](v2-ai-reliability.md)、[Streaming 退役 ADR](../architecture/adr/ADR-006-retire-streaming.md) |
| V3 | [安全治理验收](v3-completion-review.md) | [数据/PII](v3-data-governance.md)、[AI 安全](v3-ai-security.md) |
| V4 | [PR CI](v4-github-ci.md)、[最小 CD](v4b-minimal-cd.md) | 精确发布证据保存在 annotated tag v4.0-cicd |
| V5 | [验收与发布](v5-completion-review.md) | [运行证据](v5-runtime-evidence.md)、[演练](v5-operational-drill.md)、[AI 回归边界](v5-ai-operational-regression.md) |

## 设计历史

[初始总体设计](../architecture/architecture.md)、[服务决策](../architecture/service-decisions.md)、[共享业务模型](../architecture/data-model.md)、[初始路线图](implementation-roadmap.md)、[Phase 1 计划](phase-1-execution-plan.md)保留当时目标与假设。部分逻辑实体、Processing/Registry、灾备与完整 PROD 是设计目标，不能据此推断已部署。实际交付以当前图、代码和对应验收证据为准。

[ADR 目录](../architecture/adr/)保存核心技术选择；[版本路线图](version-roadmap.md)提供最终交付映射。
