# 开发标准

## 1. 适用范围与阶段纪律

本标准覆盖后续 Terraform、数据、ML、RAG 和 CI/CD 工作。Gate 1 已批准，当前停在 Phase 1 execution plan review；计划获批前不得委派实施或编写 Terraform，任何 AWS 资源创建仍需单独的 reviewed-plan 人工授权。

## 2. 工作流程

1. Manager 从获批路线图建立符合 Worker Task Contract 的任务。
2. Worker 只修改被授权文件；架构/契约/安全/服务变化返回 `ARCHITECTURE_DECISION_REQUIRED`。
3. PR 必须小而可评审，关联 task/ADR，说明风险、成本和回滚。
4. 自动检查通过后由 Manager 审查正确性、架构、安全、成本、幂等、失败处理、监控、文档。
5. `main` 可进入 DEV 部署与集成测试；PROD plan 与 apply 之间必须人工批准。

## 3. Definition of Done

适用项必须全部满足：实现、单元/DQ/集成/故障测试、格式与静态检查、Terraform 更新、日志/指标/告警、重试、隔离、对账、幂等、安全/成本评审、文档和 Manager review。仅“代码可运行”不算完成。

## 4. 编码标准

- Python 使用明确类型提示、结构化日志、UTC aware datetime 和 `decimal` 处理货币。
- 业务转换尽量写成无副作用纯函数，I/O 置于薄适配层；禁止在 import 时访问 AWS。
- 配置来自显式环境/参数/Secrets Manager；无硬编码账号、region、bucket、凭据或环境名。
- 日志包含 `run_id,pipeline_name,stage`，错误使用稳定 `error_code`；禁止秘密和非必要 PII。
- 外部调用设置 timeout；只对瞬态错误做最多 3 次有界指数退避，验证错误直接隔离/失败。
- 所有写入定义幂等键；Iceberg 使用键控 MERGE/原子提交，不允许盲目 append 当前状态表。

## 5. Terraform 标准（后续阶段）

- 结构：`terraform/bootstrap`、`terraform/modules`、`terraform/environments/dev|prod`。
- DEV/PROD remote state 分离、加密、锁定和最小访问；bootstrap 与工作负载 state 分开。
- module 不硬编码环境；输入有类型/validation，输出不暴露 secret。
- 资源需 tags、加密、日志、公共访问控制和生命周期；IAM 不得使用无理由 `*`。
- PR 至少运行 `terraform fmt -check`、`terraform validate`，配置后运行 `tflint`、`checkov` 与 plan。
- plan 必须归档并人工阅读 create/change/destroy、权限扩大、公共暴露、常驻成本和替换风险。
- 禁止控制台手建持久资源；临时调查必须预先批准、标记 owner/expiry 并清理。

## 6. 数据工程标准

- Landing 不可变；Bronze、Silver、Gold 均为 S3 上的 Iceberg 表并由 Glue Catalog 管理。
- schema 必须由版本化契约驱动；breaking change 先兼容迁移，禁止 crawler 静默改变生产表。
- 测试重复 CSV、重复 event、重复 CDC、Step Functions 重试、Glue restart、迟到/乱序和 delete。
- DQ 规则分 `ERROR`（阻断/隔离）与 `WARN`（度量/审查）；阈值写入配置并版本化。
- 每批完成计数对账；坏数据保留原始记录与原因，不直接删除或手改 Silver/Gold。
- Iceberg 作业需考虑 optimistic concurrency、small files、snapshot expiry 和 orphan cleanup，维护操作必须可审计。

## 7. ML 标准

- 数据快照、特征代码、参数、随机种子、镜像/依赖、指标和 artifact 均可追溯。
- 使用时间合理的 train/validation/test split；检查泄露、类别不平衡和关键群体表现。
- 模型晋级阈值与风险阈值由业务/模型评审批准；不达标不得注册为 Approved。
- 默认 Batch Transform；输出遵守 `claim_risk` 契约，可按 `claim_id + model_version` 重跑。
- 不记录直接 PII 特征值；模型 artifact、评估和推理结果加密并限制访问。

## 8. RAG 标准

- 仅索引获批、版本化、分类明确的文档；删除/撤销必须同步向量索引。
- 首版固定并版本化 parser、chunking、embedding model、metadata schema 和 prompt。
- 评估集覆盖检索相关性、引用准确、忠实度、越权、提示注入和无答案拒答。
- 输出必须提供来源引用；不允许用模型常识掩盖缺失检索证据。
- S3 Vectors 首版 semantic-only，超出能力的需求走 ADR。

## 9. 测试与 CI 门禁

| 层级 | 最低内容 |
|---|---|
| Unit | 转换、验证、键、状态映射、计数、特征逻辑 |
| Data Quality | null、unique、range、allowed values、FK、时间关系 |
| Integration | S3→Glue、DMS→S3、Glue→Iceberg、Gold→Athena |
| End-to-end | PostgreSQL change→CDC→Bronze/Silver/Gold→Athena |
| Failure | malformed、duplicate、negative amount、job failure、retry exhausted |
| Security | IaC scan、依赖/secret scan、IAM 和公开访问检查 |

PR 顺序：format → lint/static → unit/DQ → security → Terraform validate/plan（有 IaC 时）。集成/E2E 在隔离 DEV 运行并清理测试数据。

## 10. 依赖、版本与供应链

- 使用 lockfile/固定版本和受支持 runtime；升级单独评审并运行回归测试。
- 构建产物可重现并保留来源 commit；不执行未经审查的下载脚本。
- secret scan 阻断提交；发现凭据按泄露处理并轮换，不能只从 Git 删除。

## 11. 文档与操作

每个管道记录 owner、输入输出契约、SLA（批准后）、运行/重放、DQ、告警、恢复和成本驱动。重要决策写 ADR；runbook 与代码同 PR 更新。
