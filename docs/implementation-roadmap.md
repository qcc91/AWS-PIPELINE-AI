# 初始实施路线图

> 当前交付策略改为累计版本 V1–V5；完整定义见
> `docs/version-roadmap.md`。V1 已验收并标记，当前 V2 已授权。本文原阶段划分作为最终能力映射保留，
> 不再表示要先完成全部生产强化才打通 happy path。

## 1. 使用方式

本路线图是 Gate 1 后的计划，不是实施授权。每个阶段由 Manager 创建 Worker Task Contract，审查交付并在 AGENTS.md 定义的 gate 停止。PROD 始终需要 Gate 6 单独批准。

## 2. 阶段与依赖

| 阶段 | 主要负责人 | 交付 | 退出条件 / Gate |
|---|---|---|---|
| 0 架构与基础 | Manager | 本架构包、标准、README、路线图、ADR | Gate 1 已于 2026-09-08 批准 |
| 1 Terraform foundation | Worker 1 | bootstrap、remote state、module 骨架、DEV 网络/KMS/S3/IAM/日志基线 | fmt/validate/security/plan；Gate 2 核心基础设施评审 |
| 2 Ingestion foundations | W1 + W2 | 合成 OLTP、CSV、DMS landing、运行审计 | Batch/CDC 两种来源落地、重复与失败测试 |
| 3 Lakehouse core | W2，W1 支持 | Bronze/Silver/Gold Iceberg、Catalog/LF、DQ/quarantine/reconcile、编排监控 | 数据契约、幂等、E2E、故障测试；Gate 3 |
| 4 BI | W2 + W1 | Athena workgroup、Gold queries、QuickSight 数据集/仪表 | 指标核对、权限/扫描成本验证 |
| 5 ML | Worker 3 | 特征、XGBoost training/eval/registry/batch、claim_risk | 指标/偏差/可追溯/批推理验证 |
| 6 RAG | Worker 3，W1 支持 | 文档发布、KB/S3 Vectors、检索/引用评估 | 访问、引用、忠实度、拒答验证；与 BI/ML 一并 Gate 4 |
| 7 Production readiness | 全员，Manager 集成 | CI/CD、runbook、恢复/灾难/安全/成本/全链路测试 | Gate 5 生产就绪评审 |
| 8 PROD plan/deploy | Worker 1，Manager 审查 | PROD Terraform plan、回滚、审批后 apply | Gate 6 明确批准后方可部署 |

## 3. 推荐任务波次

### Wave A — Foundation（Gate 1 后）

- W1：remote state bootstrap 设计与 DEV foundation modules；IAM/KMS/S3/CloudTrail/CloudWatch/SNS 基线。
- Manager：region、初始 RPO/RTO 与 PII 角色基线已确认；继续确认 account、预算、保留期和身份映射，冻结 data contract v1。
- Gate 2 前不把业务管道部署到 PROD。

### Wave B — Source-to-Bronze

- W2：合成无 PII 数据、CSV schema/validator、PostgreSQL schema/data generator。
- W1：RDS/DMS/EventBridge/Step Functions DEV 基础。
- 接口：Landing prefix、run envelope、CDC envelope 和 quarantine schema 先完成契约测试。
- Bronze 对 Batch/CDC 两种来源统一采用 Iceberg，并保留源操作与审计元数据。

### Wave C — Silver/Gold

- W2 按 customer → product → policy → claim → payment 依赖顺序实现 Silver，随后实现 Gold。
- 优先端到端 claim happy path，再扩展实体；每张表同时交付重复、坏数据、重启和对账测试。
- W1 增加最小告警/仪表与 integration harness。

### Wave D — Consumers

- BI 先验证 Gold 语义和 Athena 成本。
- ML/RAG 可在 Gold/文档契约稳定后并行，但 Worker 3 不改变数据平台架构。
- RAG 首版仅受控文档、semantic retrieval、citation 与离线评估；ML 仅 batch inference。

### Wave E — Hardening

- CI/CD、恢复/重放、密钥/秘密轮换、权限负面测试、成本故障情景、Iceberg 维护、runbook 演练。
- 汇总 Gate 5；Gate 6 仅展示 reviewed PROD plan，未经明确批准不得 apply。

## 4. 验收主线

每个增量必须证明：相同输入重放不重复；瞬态失败 bounded retry；验证失败隔离可调查；计数可对账；日志无秘密/PII；权限最小；成本可归属；文档和运行手册同步。

关键 E2E：PostgreSQL 修改 claim → DMS CDC → Bronze Iceberg → Silver merge → Gold fact/risk-ready dataset → Athena 断言。并行故障路径覆盖重复 CDC、乱序、负 claim amount、Glue 失败和 retry exhaustion。

## 5. 决策/批准清单

V2 保持 Sydney、DEV-first、FREE account 与已批准成本边界。Streaming 已退出；PII 身份分离和列级治理留到 V3。

## 6. 当前停止点

V1 已验收并标记 `v1.0-happy-path`。当前仅授权 V2 可靠性与数据质量；完成真实 AWS 验证、提交和推送后停止，等待 Human 综合验收。
