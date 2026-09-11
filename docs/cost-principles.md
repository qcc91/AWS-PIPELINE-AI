# 成本原则与控制框架

## 1. 目标

用最小架构展示生产质量，而不是为假设规模预付费。所有估算默认采用 `ap-southeast-2`；DEV 变更必须在已批准工作包内，PROD 仍需单独审批。

## 2. 成本决策

- S3：少量职责 bucket、Parquet/Iceberg 压缩、生命周期转低频/删除临时数据；避免大量 tiny objects。
- Glue：事件/计划批量运行，选最小可用 worker 和超时，启用自动停止；合并小批次而不制造长时间空闲。
- RDS：DEV 采用最小规格和非使用时停机（在服务允许范围内）；PROD Multi-AZ 只在 RTO/RPO/业务价值支持时启用。
- DMS：这是潜在持续成本热点。对 provisioned 小规格与 DMS Serverless 的最低计费/启停行为做实测，再决定；DEV 不保持无用 CDC。
- Streaming：V2 起退出项目范围，不产生 Kinesis/Firehose 成本，也不引入替代服务。
- Athena：只查列式 Gold、合理分区；workgroup 设置扫描限制，避免 `SELECT *` 和全历史反复扫描。
- QuickSight：先限制作者/读者和数据集，按真实使用选择 direct query 或缓存；不预购假设容量。
- SageMaker：Processing/Training/Batch Transform 使用短时、适当小规格；无 notebook 常驻、无 persistent endpoint；artifact 生命周期清理。
- Bedrock/KB/S3 Vectors：小评估集、受控同步与 token 上限；每 KB 独立 index 但不复制无用文档；不采用 OpenSearch Serverless。
- CloudWatch：结构化且精简日志，设保留期；对高基数自定义指标和逐记录日志保持克制。
- KMS/Secrets Manager：按安全边界复用合适 key，避免无意义的每对象 key；控制 secret 数量和 API 调用，但不牺牲安全。
- NAT Gateway：默认避免。若私有工作负载的依赖无法由 service endpoint/受控路径满足，提交网络、安全和流量成本比较后决定。

## 3. 成本分类

| 类别 | 主要服务 | 风险 | 控制 |
|---|---|---|---|
| 持续计算 | RDS、DMS | 空闲仍计费 | DEV 启停、最小规格、利用率告警 |
| 作业计算 | Glue、SageMaker、CodeBuild | 失控/重试循环 | timeout、并发上限、最多 3 次重试 |
| 扫描/请求 | Athena、S3、KMS、Bedrock | 查询/token/小请求累积 | 分区压缩、预算、token/扫描限额 |
| 存储 | S3、Iceberg snapshots、模型、日志、向量 | 版本/快照无限增长 | 分层保留、生命周期、维护作业 |
| 许可证/用户 | QuickSight | 闲置席位 | 定期复核活跃用户 |
| 网络 | NAT、跨 AZ/region、公网传输 | 隐蔽且持续 | 同区、endpoint 评估、避免跨区复制 |

## 4. 环境策略

- DEV 使用合成数据，可销毁工作负载资源，保留必要审计/状态；通过 tag 与自动 expiry 防止遗忘。
- PROD 不因“低成本”跳过加密、审计、备份或告警；可用性投入由批准的业务目标决定。
- 两环境不得共享数据、密钥、state 或告警目标；共享代码 module 不等于共享资源。
- DEV 是实际实施主环境；PROD 只建立独立 environment/state 设计，未获明确批准不创建资源。
- 不以跨区域方式规避 Sydney 服务不可用；先提交架构、成本、传输和数据驻留影响供审批。

## 5. FinOps 门禁

每个 PR/plan 回答：新增哪些计费维度、是否持续运行、预计月度区间/假设、最坏重试成本、日志/数据保留、退出/清理方法。重大成本增加需 Human Owner 批准。

部署前建立：项目/环境 cost allocation tags、月度预算和分级告警、异常费用检查、服务配额。预算阈值与币种由 Human Owner 给出。

## 6. 估算方法

使用目标 region 的 AWS Pricing Calculator/官方价格，以三种情景记录假设：idle/minimum、expected、failure/high-water。至少输入：GB/月与保留期、每日批数与 Glue DPU-minutes、RDS/DMS 小时、流入 GB、Athena scanned TB、QuickSight 用户、SageMaker instance-hours、Bedrock input/output tokens 与 KB ingestion、日志 GB。

任何没有数据量依据的数字都标为假设。Gate 2 提供按服务月度估算、持续成本、一次性成本及 20–30% 不确定性缓冲，而不是在 Gate 1 给虚假精度。

## 7. 自动控制与清理

- 作业 timeout、并发上限、重试上限、DEV schedule、S3 lifecycle、CloudWatch retention。
- Iceberg snapshot expiry/orphan file removal 在保留与恢复要求批准后配置。
- 测试 run 使用标签和 run ID，集成测试完成后由受控清理流程删除临时数据。
- 月度复核闲置 RDS/DMS、旧模型、未用 BI 席位、日志异常、Athena top queries 和 bucket 增长。

安全/恢复数据的删除必须遵守已批准保留期；成本优化不能成为静默删除 quarantine 或审计证据的理由。
