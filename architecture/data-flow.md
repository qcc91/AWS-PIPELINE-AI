# 数据流与处理语义

## 1. 共用运行信封

每次文件、CDC 微批、流微批或文档同步都必须携带或关联：

| 字段 | 含义 |
|---|---|
| `run_id` | UUID，一次编排执行的关联键 |
| `pipeline_name` | 稳定管道名 |
| `source_system` | `broker_csv`、`insurance_oltp`、`app_events` 或文档来源 |
| `source_object` | S3 URI/源表/流分片与批次引用 |
| `schema_version` | 输入契约版本 |
| `ingested_at` | UTC 接收时间 |
| `file_id` / `event_id` | 幂等键；文件使用内容摘要与来源构造 |

## 2. Batch CSV

```text
Broker -> S3 landing/batch
       -> EventBridge -> Step Functions
       -> file envelope/schema validation
       -> Glue Bronze Iceberg parse/write
       -> duplicate file/row detection
       -> Silver type/business/DQ validation
       -> Iceberg MERGE
       -> Gold refresh -> reconcile -> audit/metrics
```

- 同一 `file_id` 已成功处理时返回幂等成功，不再次追加。
- 文件级 schema 不合规进入 `quarantine/schema_errors`；行解析失败进入 `parsing_errors`。
- 业务无效记录进入 `data_quality`，重复行进入 `duplicates`；均保留原始值、失败原因和 run ID。
- 文件先完整落 Landing 再触发；不处理仍在上传的对象。

## 3. PostgreSQL full load 与 CDC

```text
RDS PostgreSQL -> DMS -> S3 landing/oltp/{schema}/{table}
                      -> scheduled/event batch boundary
                      -> Bronze Iceberg with op/order metadata
                      -> Silver latest-state MERGE by PK + source order
                      -> Gold affected datasets -> reconciliation
```

- full load 建立基线，CDC 从受记录的恢复点继续；切换前验证行数和延迟。
- 每条变化保留操作类型、源提交/事件时间、DMS 顺序字段和源主键。
- Silver MERGE 使用 `(primary_key, source_order)` 判定最新记录；delete 以明确 tombstone 语义处理。
- 重复 CDC 文件或事件不得改变最终状态；迟到但 source order 更旧的记录不得覆盖新状态。
- Schema breaking change 停止受影响表并隔离，不能静默丢列或错误转换。

## 4. Streaming

```text
Producer -> Kinesis Data Streams -> Data Firehose -> S3 landing/stream
                                                  -> micro-batch trigger
                                                  -> Bronze Iceberg -> Silver dedupe
                                                  -> optional Gold aggregates
```

- producer 必须提供全局稳定 `event_id`、event type、UTC event timestamp、source 和业务 ID。
- Kinesis/Firehose 为至少一次语义设计；Silver 以 `event_id` 去重。
- 分区键优先使用稳定业务 ID 以保持同一对象局部顺序，避免单热键。
- 迟到窗口和 Gold 聚合重算范围按用例定义；原事件始终保留以便重放。
- malformed envelope 进入 parsing/schema quarantine；未知 `event_type` 不进入 Gold。

## 5. Bronze → Silver → Gold

| 转换 | 输入 | 核心处理 | 输出门禁 |
|---|---|---|---|
| Landing → Bronze Iceberg | 原始对象 | envelope、解析、源元数据、记录摘要 | schema 可识别、计数可核对 |
| Bronze → Silver | 源导向 Iceberg | 标准化、去重、CDC merge、引用和业务规则、PII 策略 | 严重 DQ 规则全过或隔离后满足阈值 |
| Silver → Gold | 可信实体 | 维度/事实/汇总/特征 | 粒度、唯一性、引用、刷新完整性 |

Gold 发布采用“构建/校验后提交”语义；任一关键输入未成功，不把部分刷新标记为最新。

## 6. BI 流

`Gold Iceberg -> Glue Catalog/Lake Formation -> Athena workgroup -> QuickSight`。Athena workgroup 设置结果位置、加密和扫描控制。数据集记录最后成功刷新 run ID；PII 仅在明确授权的数据集中出现。

BI 的维度、事实和汇总与 ML 共享同一 Silver 业务实体。产品理赔频率、地区
金额、broker 损失率和客户终身保费等指标既可用于报表，也可在严格时点截断
后成为 ML 历史特征；不得为 ML 复制一套不一致的业务事实。

## 7. ML 流

```text
Silver/Gold snapshot -> SageMaker Processing feature set
 -> train/validation/test split -> XGBoost Training
 -> evaluation thresholds -> Model Registry
 -> Batch Transform -> Gold claim_risk -> Athena/BI
```

训练记录数据快照、代码版本、参数和随机种子；避免时间泄露与目标泄露。V1
预测时点是 claim `submitted_at`，任何特征只能读取该时点前已知的数据；最终
severity、approved/paid amount、最终状态、调查结果和 settlement days 只能
用于标签或预测后评估。训练/验证/测试按预测时间切分。未达到审批阈值的模型
不得晋级。推理按 `claim_id + model_version` 幂等写入。

## 8. RAG 流

```text
Approved documents + metadata -> S3 documents
 -> Bedrock KB ingestion -> chunk/embed -> S3 Vector index
 -> Retrieve / RetrieveAndGenerate -> answer + source citations
```

文档发布需要 `document_id`、版本、来源、分类、有效期和访问级别。更新/删除要触发同步并验证陈旧 chunk 消失。首版评估检索相关性、引用正确性、忠实度和拒答行为；不得把未检索到的内容陈述为事实。

## 9. 失败、隔离和重放

```text
Transient error -> retry (max 3, exponential backoff) -> success
                                               \ -> terminal failure -> audit + metric + SNS
Validation error -> quarantine -> audit + metric -> stop dataset or continue valid subset per severity
```

重放从不可变 Landing 输入创建新 `run_id`，但沿用原 `file_id/event_id`；目标 MERGE 和完成登记共同防重。修复后的 quarantine 数据作为新纠正批次进入，不直接手改 Silver/Gold。

## 10. 对账与可观测性

每阶段至少记录 `input_count`、`output_count`、`rejected_count`、`duplicate_count`、质量分、延迟、开始/结束时间和状态。CDC 额外监控 replication lag，流额外监控 iterator age/delivery failure，Iceberg 监控小文件与快照增长。CloudWatch 只存技术标识与聚合计数，不存完整 PII 记录。
