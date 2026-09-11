# AWS 服务决策

## 1. 决策状态

本文是 Human Owner 于 2026-09-08 批准的 Gate 1 服务边界。所有服务均来自 AGENTS.md 已批准清单；默认区域为 `ap-southeast-2`。具体版本、规格和容量必须在后续 Terraform plan 前验证。

| 能力 | 决策 | 用途与理由 | 成本/运行约束 | 未选择方案 |
|---|---|---|---|---|
| 对象与表存储 | Amazon S3 | Landing、Lakehouse、quarantine、文档和产物的耐久存储 | 生命周期、压缩、按环境分离，禁止公开 | 不采用 HDFS/自建存储 |
| 表格式 | Apache Iceberg | ACID、MERGE、快照、Schema 演进，适合 CDC 与多消费者 | 定期清快照/孤儿文件、控制小文件 | 纯 Parquet 缺少可靠表事务 |
| 批处理 | AWS Glue | 批量 ETL、Iceberg 读写、数据质量 | 小型短作业、自动停止、避免空跑 | 不采用 EMR/EKS/常驻 Spark |
| Catalog | Glue Data Catalog | 表元数据和 Athena/Glue 集成 | 控制 crawler 使用，表由管道显式管理优先 | 不自建 metastore |
| 治理 | Lake Formation | 表、列和位置级授权，保护 PII | 权限即代码，区分 data access 与 IAM | 仅 bucket policy 粒度不足 |
| 编排 | Step Functions | 可视状态、重试、错误分支和审计关联 | Standard/Express 选择在执行频率验证后决定 | 不使用自建调度器 |
| 触发 | EventBridge | S3 到达、计划任务和事件路由 | 合并/过滤事件，幂等处理重复投递 | 不轮询 S3 |
| OLTP | RDS for PostgreSQL | 模拟核心保险事务源 | 小规格、DEV 可停机；PROD HA 需需求支持 | 不自管 EC2 PostgreSQL |
| CDC | AWS DMS | PostgreSQL full load + CDC 到 S3 | 复制计算是主要持续成本之一；规格/Serverless 需成本测试 | 不自写 WAL 消费器 |
| 流式入口 | 不采用 | V2 起 Streaming 由 Human 主动退出项目范围 | 无持续成本 | 不引入替代流技术；见 ADR-006 |
| 查询 | Athena | 对 Gold Iceberg 做 serverless SQL | 列式格式、分区、workgroup 扫描限制 | 不采用 provisioned Redshift |
| BI | QuickSight | Gold 数据集的托管可视化 | 作者/读者数量和缓存策略部署前确认 | 不建自托管 BI |
| ML | SageMaker | Processing、Training、Registry、Batch Transform | XGBoost、短时作业、无持久 endpoint | 不建实时 endpoint |
| RAG | Bedrock + Knowledge Bases | 托管 ingestion/retrieval/generation 与引用 | 按 token/ingestion 计量，限制同步频率 | 不建复杂 agent 工作流 |
| 向量存储 | Amazon S3 Vectors | 低成本语义向量存储、与 KB 集成 | 首版接受 semantic-only；一 KB 一 index | 不采用 OpenSearch Serverless |
| 监控/告警 | CloudWatch + SNS | 指标、日志、仪表和可操作通知 | 日志保留、告警聚合、无敏感内容 | 不引入第三方监控 |
| 秘密/加密 | Secrets Manager + KMS | 凭据托管和静态加密控制 | 控制 secret 数量、轮换与 KMS 调用 | 不把秘密放代码/Parameter Store |
| 审计 | CloudTrail | AWS API 控制面审计 | 日志集中、受限、生命周期管理 | 应用日志不能代替审计 |
| CI/CD | GitHub + CodePipeline + CodeBuild | PR 验证和审批式部署 | 短构建、缓存审慎、PROD 人工审批 | 不自动 PROD apply |

## 2. 关键服务边界

- DMS 只负责把 full load/CDC 可靠落到 Landing；Glue 负责解释操作顺序并 MERGE 至 Iceberg。
- Batch/File 与 PostgreSQL CDC 共用同一 Bronze/Silver/Gold Lakehouse；来源机制不同不等于复制 Medallion 架构。
- Glue crawler 不作为受控 Iceberg 业务契约的唯一 schema 管理方式；契约变更需显式评审。
- Athena/QuickSight 只面向获批 Silver/Gold 数据，不直接读取 PII 原始区。
- SageMaker 和 Bedrock 复用数据平台的身份、审计和 S3 数据源，不另建数据湖。
- S3 Vectors 首版仅语义搜索。需要 hybrid search、高 QPS 或复杂聚合时必须提出新的 ADR，不得默认引入 OpenSearch。

## 3. 延后到详细设计的选择

以下仍延后到后续批准版本：RDS/DMS 生产规格、QuickSight edition/capacity、Bedrock 模型演进和 S3 物理整合。选择标准是 Sydney 可用性、最小满足、安全和总成本。任何需要第二区域的情况必须先返回 `ARCHITECTURE_DECISION_REQUIRED`。

## 4. ADR 索引

- [ADR-001：使用 Apache Iceberg](adr/ADR-001-use-iceberg.md)
- [ADR-002：使用 Step Functions](adr/ADR-002-use-step-functions.md)
- [ADR-003：Athena 替代 Redshift](adr/ADR-003-athena-instead-of-redshift.md)
- [ADR-004：S3 Vectors 用于 RAG](adr/ADR-004-s3-vectors-for-rag.md)
- [ADR-005：使用批量推理](adr/ADR-005-batch-inference.md)

## 5. 官方能力依据

- Glue 3.0+ 支持在 S3 上读写 Iceberg，并可用 Glue Data Catalog：[AWS Glue Iceberg 文档](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-programming-etl-format-iceberg.html)
- DMS S3 target 支持 full load/CDC、Parquet 和 KMS 配置：[DMS S3 target 文档](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html)
- S3 Vectors 可作为 Bedrock Knowledge Bases vector store，检索响应支持原始来源引用：[S3 Vectors + Bedrock KB 文档](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html)
