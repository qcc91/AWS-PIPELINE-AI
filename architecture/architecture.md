# 总体架构

## 1. 状态与范围

- 状态：Gate 1 已由 Human Owner 于 2026-09-08 批准
- 阶段：Phase 1 计划评审中；尚未授权实施或部署
- 目标：以最小成本展示生产质量的数据与 AI 工程能力
- 规模假设：数据量小、吞吐低、非实时欺诈评分可接受；具体容量在部署前用测量值校准
- 主区域：`ap-southeast-2`（Sydney）；所有服务默认部署在该区域
- 环境：DEV 是实施和实际部署的主环境；PROD 保留独立 Terraform environment/state 设计，未获明确批准不部署 PROD 资源

## 2. 架构原则

1. 一个受治理的数据平台，BI、ML、RAG 不建立各自的数据湖。
2. 原始证据不可变且可重放；标准化和业务语义逐层增强。
3. 写入幂等、重试有界、失败可见、坏数据可调查。
4. PII 默认拒绝访问；按角色和数据层授予最小权限。
5. 小规模优先 serverless/on-demand/batch，持续运行资源必须有业务理由。
6. 所有持久资源通过 Terraform；所有 PROD 变更需人工审批。
7. 不因服务或模型在 Sydney 不可用而静默采用第二区域；必须返回 `ARCHITECTURE_DECISION_REQUIRED`，列出替代方案、成本和安全影响。

## 3. 逻辑架构

```text
┌──────────────────── Sources ────────────────────┐
│ Broker CSV       RDS PostgreSQL       App events│
└──────┬────────────────┬──────────────────┬──────┘
       │                │ DMS full+CDC     │ Kinesis
       │                │                  v
       │                │             Data Firehose
       └────────────────┴──────────────────┬──────┐
                                           v      │
                                   S3 Landing     │
                                           │ EventBridge
                                           v      │
                                  Step Functions <┘
                                           │
                  ┌────────────────────────┴──────────────────────┐
                  v                        v                      v
             Glue ETL                Glue Data Quality       Quarantine
                  │
                  v
 S3 + Iceberg: Bronze ─────> Silver ─────> Gold
                  │              │            │
                  └──────────────┴────────────┤
                                              ├─ Athena ─ QuickSight
                                              ├─ SageMaker Processing/Training/
                                              │  Registry/Batch Inference
                                              └─ approved downstream use

 S3 governed documents ─> Bedrock Knowledge Bases ─> S3 Vectors
                                      │
                                      └─ Retrieve/Generate with source citations

 Cross-cutting: Glue Catalog, Lake Formation, IAM, KMS, Secrets Manager,
 CloudWatch, SNS, CloudTrail, GitHub + CodePipeline/CodeBuild
```

RAG 的非结构化文档区与 Lakehouse 共用治理、安全、审计和生命周期原则，但不把文档伪装成 Gold 表。结构化业务上下文若用于 RAG，必须由 Silver/Gold 受控导出，保留来源和版本。

## 4. 数据分区与存储边界

建议按环境使用少量职责清晰的 S3 bucket，而不是为每个表建 bucket：

| 逻辑存储 | 用途 | 可变性 | 关键控制 |
|---|---|---|---|
| landing | CSV、DMS full/CDC、Firehose 原始对象 | 追加、不可就地改写 | 版本控制、SSE-KMS、生命周期、来源前缀 |
| lakehouse | Bronze/Silver/Gold Iceberg 数据 | 仅管道角色写 | Glue Catalog、Lake Formation、快照维护 |
| quarantine | schema/DQ/duplicate/parsing 失败 | 追加，按保留策略清理 | 严格访问、原因与原始记录 |
| documents | RAG 原始文档及元数据 | 受控发布 | 版本、分类、来源、访问级别 |
| artifacts | ML 模型/评估、作业临时产物、日志导出 | 工作负载管理 | 生命周期、模型版本、不可公开 |

是否合并低风险 bucket 由后续 Terraform 设计根据策略复杂度决定，但不同环境不得混用前缀作为唯一隔离手段。

建议键结构：`source=<source>/entity=<entity>/ingest_date=YYYY-MM-DD/run_id=<uuid>/...`。Gold 的查询分区只采用有实际过滤价值、基数受控的业务日期；不按 `run_id` 分区 Iceberg 表。

## 5. 分层责任

### Landing

接收源文件/记录，保持字节级或消息级原貌。生成稳定 `file_id`（内容摘要 + 来源）或保留 `event_id`，记录对象校验和、来源、接收时间和 run ID。对象到达仅触发编排，不代表质量通过。

### Bronze

最小解析为源导向 Iceberg 表，保留源字段和 CDC 操作/顺序；添加 `_run_id`、`_ingested_at`、`_source_system`、`_source_object`、`_record_hash`、`_schema_version`。解析失败进入 quarantine。

### Silver

统一类型、UTC 时间、编码和状态值；依据业务键/事件 ID 去重；按源顺序应用 CDC；验证引用关系和 PII 处理。严重规则失败阻止该数据集晋级，坏记录进入 quarantine。

### Gold

形成维度、事实与派生数据集：`dim_customer`、`dim_policy`、`dim_product`、`fact_claim`、`fact_payment`、`customer_360`、`claim_daily_summary`、`policy_performance`、`claim_risk`。每个数据集拥有刷新时点、粒度、负责人、DQ 阈值和数据契约。

## 6. 控制流和运行状态

EventBridge 接收 S3 到达或调度事件，启动 Step Functions。标准状态机为：

```text
RegisterRun -> ValidateEnvelope -> ProcessBronze -> GateBronzeDQ
 -> ProcessSilver -> GateSilverDQ -> ProcessGold -> Reconcile -> PublishSuccess
          \ on terminal failure -> RecordFailure -> Metric/Alert -> Fail
```

- 每个执行使用 UUID `run_id`，审计记录包含计数、时间、阶段、状态和错误摘要。
- Glue/SDK 调用默认最多 3 次尝试、指数退避和抖动；验证错误不重试。
- 每一步先检查输入身份与已完成状态；重复 S3 事件、Step Functions 重试或 Glue 重启不得重复写入。
- `input_count = output_count + rejected_count`；去重数单列，因此必要时使用 `input_count = accepted_before_dedup + rejected_count` 并记录 `duplicate_count`。
- 告警按影响分级，避免每个坏记录触发 SNS 风暴；任务终止、持续延迟、对账失败和 DQ 门禁失败才通知。

审计存储的最终实现形式（Iceberg 审计表或轻量 S3 记录）留到详细设计，但不得引入未批准服务。

## 7. 安全与治理

- S3 全面启用 Block Public Access、TLS-only bucket policy、默认 SSE-KMS；密钥按环境/数据域控制，启用轮换策略。
- RDS 凭据仅存 Secrets Manager；代码、Terraform 变量默认值和 CI 日志不得出现秘密。
- IAM 按服务和阶段拆分角色：ingestion、orchestration、Glue、analytics、ML、Bedrock、CI/CD；禁止共享管理员角色。
- Lake Formation 管理数据库/表/列权限；PII 列仅对获批角色开放，分析层优先暴露去标识或最小字段视图/表。
- RDS 不公开访问；安全组只允许明确的数据迁移/管理路径。具体 VPC 端点与是否需要 NAT 在网络详细设计时以成本和可达性验证，默认避免 NAT Gateway。
- CloudTrail 记录控制面活动；CloudWatch 日志不得含秘密、完整文档正文或非必要 PII。
- PROD CI/CD 使用人工审批，且部署角色与审批者职责分离。

已批准的初始数据访问角色如下：

| 角色 | 默认数据范围 | PII 原则 |
|---|---|---|
| `DataEngineer` | 按管道职责访问 Bronze/Silver/Gold | 仅在开发、质量、隔离调查确有需要时访问，操作可审计 |
| `Analyst` | 主要访问 Gold | 直接 PII 默认拒绝，使用屏蔽、去标识或受限列 |
| `MLEngineer` | 经批准的 Silver/Gold 数据集 | 只授予特征所需的最少 PII，不默认访问 Bronze |
| `RAGApplication` | 经批准的 S3 文档源和对应向量索引 | 禁止不受限客户 PII，不读取通用 Bronze/Silver/Gold 客户数据 |

这些是初始角色边界，不等同于给所有同名主体授予权限。后续必须将其展开为 Lake Formation/IAM grant matrix，并执行允许和拒绝路径测试。

## 8. 可用性、恢复与运维

- S3 为事实存储，利用版本控制、Iceberg 快照和明确保留期支持恢复；恢复演练包含误删/坏批次回滚。
- 初始项目假设：batch analytics RPO 为 24 小时，analytical pipeline RTO 为 4 小时；它们是项目假设，不是真实业务 SLA。
- Streaming 为 best-effort near-real-time，不属于生命关键型事务工作负载；其重放与监控仍需满足生产工程要求。
- DMS、Kinesis、Firehose、Glue、Step Functions 指标进入 CloudWatch；SNS 通知到环境对应渠道。
- Runbook 应覆盖重放、隔离修复、CDC 延迟、Schema 演进、Iceberg 小文件/快照维护、密钥与凭据轮换。
- 小数据量不引入跨区域复制、多区域主动主动或常驻灾备计算；如 PROD 业务目标要求，必须提交 ADR、成本和安全影响供批准。

## 9. 分支架构

### BI

Athena 查询 Gold Iceberg，QuickSight 使用按需查询或经成本验证后的缓存策略。消费者不得绕过 Gold 直接解释 Landing。

### ML

SageMaker Processing 从受治理 Silver/Gold 构建带版本的数据集；XGBoost 执行 train/validation/test，评估达标后注册模型；批量推理写入 `claim_risk`，包含 `claim_id`、概率、风险级别、模型版本和预测时间。不创建持久 endpoint。

### RAG

获批文档进入 S3 文档区，Bedrock Knowledge Bases 分块并使用选定 embedding model 写入独立 S3 Vector index。第一版仅语义检索，返回源文档引用；访问过滤、文档分类、提示防注入和评估必须在启用前验证。Sydney 当前提供 Bedrock runtime 与 S3 Vectors，但仍须在部署时复核 Knowledge Bases、具体 embedding/生成模型、配额及集成兼容性。

## 10. 架构约束与待确认项

Gate 1 已批准逻辑架构，但不等于授权部署。以下细节在后续 gate 前仍需确认：

- AWS account 策略、数据保留期和数据驻留要求；
- RDS/DMS 的 DEV 启停策略与 PROD 高可用需求；
- 四类角色的列级 grant、PII 脱敏规则与身份映射；
- 可用 Bedrock 模型、区域和配额；
- 实测数据量、吞吐、Glue 作业时长和成本预算阈值。

任何新增 AWS 服务、常驻资源、架构/契约/安全/后端策略变化都需 Manager 评审；重大变化返回 Human Owner 审批。

## 11. 参考

- [AWS Glue 对 Iceberg 的支持](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-programming-etl-format-iceberg.html)
- [DMS 以 S3 为目标及 CDC/Parquet 配置](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html)
- [S3 Vectors 与 Bedrock Knowledge Bases](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html)
- [Bedrock endpoint 区域可用性](https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints-region-availability.html)
- [S3 Vectors GA 区域（包含 Sydney）](https://aws.amazon.com/blogs/aws/amazon-s3-vectors-now-generally-available-with-increased-scale-and-performance/)
