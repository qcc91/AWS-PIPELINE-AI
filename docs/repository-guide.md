# 仓库结构与阅读指南

本次结构重构以已验收的 V5 平台为基础，只改变文件组织和路径引用，不改变业务
逻辑、Terraform 资源、AWS 架构、安全模型或 CI/CD 行为。V1–V5 annotated tags
继续指向原有提交，历史运行 ID、查询 ID、执行 ID 和验收证据全部保留。

## 当前职责目录

| 责任 | 当前目录 | 内容 |
|---|---|---|
| 数据平台 | `pipelines/` | Batch/CDC ingestion、阶段转换与质量/重放工具 |
| 业务与 AI | `workloads/` | BI SQL、ML、RAG 与批准的知识源文档 |
| 平台工程 | `infrastructure/` | Terraform、CodeBuild buildspec 与一致性检查 |
| 测试 | `tests/` | 单元、静态、数据质量与集成契约测试 |
| 文档 | `docs/` | 当前架构、运维、安全、发布证据与历史设计 |
| Agent 工程 | `agents/` | Canonical `AGENTS.md` 与持久状态 |

GitHub 的运行约束要求 active workflow 继续位于 `.github/workflows/`；它在逻辑上
仍属于 Infrastructure/CI-CD。根目录 `AGENTS.md` 只是兼容入口，唯一 canonical
规则位于 `agents/AGENTS.md`。

## 旧路径到新路径

| 旧位置 | 新位置 |
|---|---|
| `src/batch/`、Batch Glue/job/script | `pipelines/ingestion/batch/` |
| `src/cdc/`、CDC Glue/SQL | `pipelines/ingestion/cdc/` |
| `src/reliability/`、V5 drill | `pipelines/quality/` |
| BI SQL/设计 | `workloads/bi/` |
| `src/ml/` 与 ML job/script | `workloads/ml/` |
| `src/rag/`、`documents/rag/approved/` | `workloads/rag/` |
| `terraform/` | `infrastructure/terraform/` |
| `buildspecs/`、CI consistency script | `infrastructure/cicd/` |
| `architecture/`、散落的 `docs/` | `docs/architecture/` 及其他职责子目录 |
| `agent-state/` | `agents/state/` |
| 根 `AGENTS.md` | `agents/AGENTS.md`（根保留兼容入口） |

## 推荐阅读顺序

1. [README](../README.md)与[四张当前图](architecture/)了解范围。
2. [数据可靠性](releases/v2/v2-data-reliability.md)了解阶段、幂等、隔离与 CDC 语义。
3. [V3 验收](releases/v3/v3-completion-review.md)了解真实授权结果。
4. [CI](releases/v4/v4-github-ci.md)与[CD](releases/v4/v4b-minimal-cd.md)了解部署边界。
5. [运行手册](operations/runbooks/)与[V5 验收](releases/v5/v5-completion-review.md)了解恢复、告警与限制。

## 容易误读的历史材料

- `workloads/ml/claim_fraud.py` 和四行 fraud fixtures 是早期 smoke 契约，包含预测后字段，不是正式模型的特征定义。最终风险模型使用 `workloads/ml/claim_risk.py`；不要据历史文件名推断最终用例。
- Model package group 的 Terraform 定义不代表已验证完整模型版本注册/审批流程；实际证据为模型 artifact、评估、批量输出和 lineage。
- `docs/architecture/data-model.md` 的逻辑实体覆盖面大于实际 PostgreSQL 五张表与已实施文件参考集。
- `agents/state/data/status.md` 是早期工作包快照，`agents/state/data-engineering/status.md` 记录后续 V5 工作；二者不是两套数据平台。
- `data/sample/` 与 `data/file_sources/` 是不同版本和用途的受控合成 fixture，不是可删除的生成垃圾。
- `infrastructure/terraform/environments/prod/` 是完整平台设计；已部署的最小 PROD proof 位于 `infrastructure/terraform/cicd-proof/prod/`。
- CDC 从保留 DMS 历史重建当前态，不能描述为规模化增量 watermark 系统或跨表原子事务。
- 安全、成本与初始架构文档可能包含未实施目标；当前声明以最终图和真实验收结果为准。

## 历史证据策略

`docs/releases/` 保存各版本验收与真实运行证据，`docs/historical/` 保存早期设计和
计划。结构重构不会重写其中的运行结果、时间线或标识符；仅修正仍需点击或执行的
仓库路径。历史正文中明确属于当时目录契约的路径可以保留，并按历史上下文阅读。
