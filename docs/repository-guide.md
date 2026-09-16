# 仓库审计与阅读指南

本次作品集整理以已验收提交 `5e0b479fa47130930dd9d4c0b0ad1005244ff335` 为基线，先审计 Git 跟踪目录、版本历史与 V1–V5 标签，再编辑展示文档。审计基线共 259 个跟踪文件；不以本机缓存作为发布内容。

## 分类与处理

| 分类 | 位置 / 发现 | 处理 |
|---|---|---|
| A 核心实现 | terraform、jobs、src、sql、scripts、buildspecs、.github | 保持路径和执行行为 |
| B 架构/文档 | architecture、docs、README、模块 README | 补充当前图、导航、历史提示 |
| C 测试 | tests、data/sample、data/file_sources | 保留全部测试和合成 fixture |
| D Agent/状态 | AGENTS、agent-state | 当前 Manager 状态更新，历史记录保留 |
| E 临时/调试 | 未发现被跟踪的 state、plan、缓存或调试产物 | 无需删除；现有 ignore 保留 |
| F 过时说明 | “V2 已授权”“V5 待验收”等阶段表述 | 历史文档加提示，当前入口标明 V5 已发布 |
| G 重复材料 | 独立 Terraform roots 的版本与 lock 文件 | 环境隔离所需，不去重 |
| H 易混淆命名 | claim_fraud、两个 data Worker 状态目录 | 用说明区分，不批量重命名 |
| I 历史证据 | ADR、验收报告、运行/查询 ID、V1–V5 标签 | 全部保留，不改发布标签 |

没有删除或移动文件，没有实现代码、测试、Terraform、CI/CD 配置变更。

## 阅读顺序

1. [README](../README.md)与[四张当前图](README.md)了解范围。
2. [数据可靠性](v2-data-reliability.md)了解阶段、幂等、隔离和 CDC 语义。
3. [V3 验收](v3-completion-review.md)了解真实授权结果。
4. [CI](v4-github-ci.md)与[CD](v4b-minimal-cd.md)了解不同部署边界。
5. [运行手册](runbooks/)与[V5 验收](v5-completion-review.md)了解恢复、告警与限制。

## 容易误读的历史材料

- `src/ml/claim_fraud.py` 和四行 fraud fixtures 是早期 smoke 契约，包含预测后字段，不是正式模型的特征定义。最终风险模型使用 `src/ml/claim_risk.py`，训练入口的历史文件名仍含 fraud；不要据文件名推断用例。
- Model package group 的 Terraform 定义不代表已验证完整模型版本注册/审批流程；实际证据为模型 artifact、评估、批量输出和 lineage。
- `architecture/data-model.md` 的完整逻辑实体覆盖面大于实际 PostgreSQL 五张表与已实施文件参考集。
- `agent-state/data/status.md` 保留较早工作包快照，`agent-state/data-engineering/status.md` 记录后续 V5 工作；二者不是两套数据平台。
- `data/sample/` 与 `data/file_sources/` 是不同版本和用途的受控合成数据，不是可随意删除的生成垃圾。
- `terraform/environments/prod/` 是完整平台设计；已部署的最小 PROD 位于 `terraform/cicd-proof/prod/`。
- CDC 从保留 DMS 历史重建当前态，不能描述为已完成规模化增量 watermark 系统或跨表原子事务。
- 安全、成本与初始架构文档可能包含尚未实施的目标；当前声明以最终图与真实验收结果为准。
