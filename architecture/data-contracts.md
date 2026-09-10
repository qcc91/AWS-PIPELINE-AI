# 数据契约

## 1. 契约规则

- 契约版本使用整数 `schema_version`；兼容新增可空字段为 minor 演进，删除/改名/缩窄类型、改变键或语义为 breaking change，必须新版本和消费者评审。
- 标识符为非空 UTF-8 字符串，去除首尾空格但不改变大小写，除非源系统契约另有说明。
- 时间戳以 ISO 8601 UTC 写入，Iceberg 使用带时区时间戳；业务日期使用 `date`。
- 金额使用 `decimal(18,2)`，同时携带 ISO 4217 `currency_code`；禁止 float。
- 原始 PII 仅进入受限 Bronze/Silver；Gold 默认使用 `customer_id` 或批准的去标识字段。
- 每张 Bronze/Silver/Gold 表至少有 `_run_id`、`_source_system`、`_ingested_at`、`_record_hash`；Gold 再有 `_effective_at`。
- `not null`、唯一性、允许值、范围和引用规则是发布门禁，不只是文档提示。

### 初始消费访问契约

| 角色 | 契约允许范围 | 明确限制 |
|---|---|---|
| `DataEngineer` | 职责所需 Bronze/Silver/Gold、quarantine 调查 | 不得批量导出或记录无必要 PII |
| `Analyst` | Gold business-ready 数据集 | PII 默认 masked/restricted；无 Landing/Bronze 访问 |
| `MLEngineer` | 获批 Silver/Gold 特征与标签字段 | 逐数据集批准最小 PII；无通用客户表访问 |
| `RAGApplication` | 获批 document IDs/metadata/vector index | 不得访问不受限客户 PII 或通用结构化客户层 |

具体列级矩阵在 Phase 1 详细设计中固化为 Lake Formation/IAM 权限测试。任何新增消费者角色或扩大 PII 范围属于安全评审事项。

## 2. Customer

粒度：每个 `customer_id` 一条当前 Silver 记录；历史策略在详细设计中选择 Iceberg 快照或 SCD，不在 Gate 1 预设。

| 字段 | 类型 | 必填 | 分类/规则 |
|---|---|---:|---|
| `customer_id` | string | 是 | PK，不可空、唯一 |
| `first_name` | string | 是 | PII，非空 |
| `last_name` | string | 是 | PII，非空 |
| `date_of_birth` | date | 是 | PII，不晚于当前日期；年龄合理性阈值待业务确认 |
| `email` | string | 否 | PII，格式验证，标准化大小写 |
| `phone` | string | 否 | PII，E.164（可转换时） |
| `address` | struct/string | 否 | PII，原始与标准化边界后续确定 |
| `customer_status` | string | 是 | `ACTIVE`,`INACTIVE`,`DECEASED`,`CLOSED` |
| `created_at`,`updated_at` | timestamp | 是 | UTC，`updated_at >= created_at` |

## 3. Product

| 字段 | 类型 | 必填 | 规则 |
|---|---|---:|---|
| `product_id` | string | 是 | PK，唯一 |
| `product_code` | string | 是 | 业务唯一 |
| `product_name` | string | 是 | 非空 |
| `product_type` | string | 是 | 受控词表，词表由业务确认 |
| `product_status` | string | 是 | `ACTIVE`,`INACTIVE`,`RETIRED` |
| `effective_from` | date | 是 | 生效起日 |
| `effective_to` | date | 否 | 空或晚于 `effective_from` |
| `created_at`,`updated_at` | timestamp | 是 | UTC |

## 4. Policy

| 字段 | 类型 | 必填 | 规则 |
|---|---|---:|---|
| `policy_id` | string | 是 | PK，唯一 |
| `policy_number` | string | 是 | 受限敏感标识，业务唯一 |
| `customer_id` | string | 是 | FK → customer |
| `product_id` | string | 是 | FK → product |
| `policy_status` | string | 是 | `QUOTED`,`ACTIVE`,`LAPSED`,`CANCELLED`,`EXPIRED` |
| `start_date` | date | 是 | `< end_date` |
| `end_date` | date | 是 | `> start_date` |
| `premium_amount` | decimal(18,2) | 是 | `>= 0` |
| `currency_code` | string(3) | 是 | ISO 4217 |
| `created_at`,`updated_at` | timestamp | 是 | UTC |

## 5. Claim

| 字段 | 类型 | 必填 | 规则 |
|---|---|---:|---|
| `claim_id` | string | 是 | PK，唯一 |
| `claim_number` | string | 是 | 受限敏感标识，业务唯一 |
| `policy_id` | string | 是 | FK → policy |
| `customer_id` | string | 是 | FK → customer，且与保单客户一致 |
| `claim_status` | string | 是 | `SUBMITTED`,`UNDER_REVIEW`,`APPROVED`,`REJECTED`,`PAID`,`CLOSED` |
| `incident_date` | date | 是 | 不晚于提交日期；是否须在保期内由业务确认 |
| `submitted_at` | timestamp | 是 | UTC |
| `claim_amount` | decimal(18,2) | 是 | `>= 0` |
| `approved_amount` | decimal(18,2) | 否 | `>= 0` 且通常 `<= claim_amount`，例外需原因 |
| `currency_code` | string(3) | 是 | ISO 4217 |
| `description` | string | 否 | 可能含 PII/敏感自由文本，不写日志 |
| `updated_at` | timestamp | 是 | UTC，`>= submitted_at` |

## 6. Payment

| 字段 | 类型 | 必填 | 规则 |
|---|---|---:|---|
| `payment_id` | string | 是 | PK，唯一 |
| `claim_id` | string | 否 | FK → claim；保费支付可为空 |
| `policy_id` | string | 是 | FK → policy |
| `payment_type` | string | 是 | `PREMIUM`,`CLAIM_PAYOUT`,`REFUND` |
| `payment_status` | string | 是 | `PENDING`,`SUCCEEDED`,`FAILED`,`REVERSED` |
| `payment_amount` | decimal(18,2) | 是 | `>= 0`；方向由 type 表示 |
| `currency_code` | string(3) | 是 | ISO 4217 |
| `payment_timestamp` | timestamp | 是 | UTC |
| `provider_reference` | string | 否 | 受限敏感标识，不存卡号/银行秘密 |
| `created_at`,`updated_at` | timestamp | 是 | UTC |

## 7. Streaming Event Envelope

```json
{
  "schema_version": 1,
  "event_id": "evt_01...",
  "event_type": "CLAIM_SUBMITTED",
  "event_timestamp": "2026-09-08T04:15:22.123Z",
  "source": "claims-api",
  "customer_id": "cus_...",
  "policy_id": "pol_...",
  "claim_id": "clm_...",
  "payment_id": null,
  "correlation_id": "corr_...",
  "payload": {}
}
```

通用必填字段：`schema_version,event_id,event_type,event_timestamp,source,payload`，且至少一个相关业务 ID。`event_id` 全局唯一；payload 中禁止凭据、卡数据和无必要 PII。

| event_type | 必需业务 ID | payload v1 最小字段 |
|---|---|---|
| `QUOTE_CREATED` | `customer_id`,`policy_id` | `product_id`, `quoted_premium`, `currency_code` |
| `POLICY_VIEWED` | `policy_id` | `channel` |
| `CLAIM_SUBMITTED` | `claim_id`,`policy_id`,`customer_id` | `claim_amount`, `currency_code` |
| `LOGIN` | `customer_id` | `result`, `channel`；不含认证材料 |
| `PAYMENT_ATTEMPT` | `payment_id`,`policy_id` | `payment_amount`,`currency_code`,`result` |

## 8. CDC Envelope

Bronze CDC 必须能够表达：`source_schema`、`source_table`、`operation` (`I/U/D`)、`primary_key`、`source_commit_timestamp`、稳定的 `source_order`、`before`（可用时）、`after`、`dms_file_id`、`_run_id`。若源顺序无法可靠建立，禁止执行会覆盖当前状态的 MERGE，先隔离并告警。

## 9. Gold 契约

| 数据集 | 粒度/键 | 主要用途 | 刷新与关键门禁 |
|---|---|---|---|
| `dim_customer` | customer | BI/关联 | customer 唯一，默认去除直接 PII |
| `dim_policy` | policy | BI/ML | policy 唯一，FK 完整 |
| `dim_product` | product | BI | product 唯一，有效期不重叠 |
| `fact_claim` | claim | BI/ML | claim 唯一、金额非负、FK 完整 |
| `fact_payment` | payment | BI | payment 唯一、金额非负、FK 完整 |
| `customer_360` | customer + as_of_date | 分析/特征 | 来源时间一致、无未来信息 |
| `claim_daily_summary` | event_date/status/product | BI | 与 fact_claim 可对账 |
| `policy_performance` | policy/product + period | BI | 指标定义和分母可追溯 |
| `claim_risk` | claim + model_version | ML/BI | 高风险概率 `[0,1]`，模型版本必填 |

`claim_risk` 首次发布的最小字段：`claim_id`,
`high_risk_probability decimal(6,5)`, `risk_level LOW|MEDIUM|HIGH`,
`model_version`, `prediction_timestamp`, `_run_id`。此前尚未产生真实输出的
`fraud_probability` 草案被本契约取代；风险阈值必须由模型评估/业务批准，
不能在契约中随意固定。

## 10. 审计与隔离契约

审计记录：`run_id,pipeline_name,source,stage,status,start_time,end_time,input_count,output_count,rejected_count,duplicate_count,quality_score,error_code,error_message`。错误消息必须脱敏且有长度限制。

隔离记录：`quarantine_id,run_id,source_object,entity,error_category,error_code,error_reason,quarantined_at,schema_version,original_record`。`original_record` 加密且仅限调查角色；不得静默删除。保留期由数据治理批准。

## 11. BI/ML 共享模型扩展契约

当前 V1 已实现的五个核心实体保持向后兼容。以下字段和实体是同一保险业务
模型的后续兼容扩展，不是 ML 专用数据源；实施状态见 `docs/data-dictionary.md`。

### 核心实体兼容扩展

| 实体 | 新增字段 | 类型/规则 |
|---|---|---|
| customer | `region`,`customer_since_date`,`customer_segment`,`household_type`,`preferred_channel` | region/segment/channel 为受控词表；since 不晚于任何保单开始日 |
| product | `risk_category` | 受控低/中/高业务类别，不得等同 ML 标签 |
| policy | `broker_id`,`renewal_date`,`sum_insured`,`deductible_amount`,`coverage_count`,`payment_frequency`,`policy_tenure_days` | 金额非负；count 非负；tenure 由时点派生而非源真值 |
| claim | `claim_type`,`reported_at`,`paid_amount`,`severity`,`incident_region`,`closed_at`,`settlement_days` | reported 不早于 incident；approved/paid/status/severity/settlement 可能为结果字段 |
| payment | `payment_method` | 受控词表，不保存卡号或银行秘密 |

Customer 中现有 `address` 字段在 address 实体实施后仅作为兼容输入，Silver
规范化后不得与 `address_current` 形成两个权威地址来源。ML 使用由 DOB 在
`as_of_timestamp` 派生的 age/age band，不直接使用 DOB。

### 新共享实体

| 实体 | 键 | 最小字段与约束 |
|---|---|---|
| address | `address_id` | `customer_id` FK、`address_type`,`region`,`postal_area`,`valid_from`,`valid_to`; 完整地址为 PII，ML 默认只用 region |
| broker | `broker_id` | `branch_id`,`region`,`commission_rate decimal(7,6)`,`active_flag`,`valid_from`,`valid_to`; commission 在 `[0,1]` |
| policy_coverage | `policy_coverage_id` | `policy_id` FK、`coverage_type`,`coverage_limit decimal(18,2)`,`deductible_amount decimal(18,2)`,`effective_from`,`effective_to`,`active_flag` |
| claim_item | `claim_item_id` | `claim_id` FK、`item_type`,`claimed_amount`,`approved_amount`,`item_status`,`created_at`,`updated_at` |
| policy_status_history | `policy_id + status_change_time + source_order` | `previous_status`,`new_status`,`reason_code`,`status_change_time`,`source_order`；不可覆盖历史 |
| claim_status_history | `claim_id + status_change_time + source_order` | `previous_status`,`new_status`,`reason_code`,`status_change_time`,`source_order`；不可覆盖历史 |
| interaction_history | `event_id` | 复用 Streaming envelope 和业务 ID；payload 禁止秘密/无必要 PII |

### Silver 发布契约

Silver 采用 `*_current` 当前实体和不可变历史表：
`customer_current,address_current,product_current,broker_current,policy_current,
policy_coverage_current,claim_current,claim_item_current,payment_current,
policy_status_history,claim_status_history,interaction_history`。

当前表必须保留源 `updated_at`；历史表必须含 `valid_from`,`valid_to`,
`recorded_at`,`source_order`。`customer_claim_history` 只能作为支持业务时间过滤
的可重建视图，不得预先混入未来结果。

### Gold BI 与特征契约

BI Gold 扩展为 `dim_customer,dim_product,dim_policy,dim_broker,dim_date,
fact_claim,fact_payment,fact_policy_transaction,customer_360,
policy_performance,broker_performance,claim_daily_summary`。

共享特征集：

| 数据集 | 键 | 必需字段 |
|---|---|---|
| `customer_claim_features` | `customer_id + as_of_timestamp + feature_version` | 30/365 日既往理赔次数、365 日既往金额、有效保单数、客户存续日、90 日支付失败数 |
| `policy_risk_features` | `policy_id + as_of_timestamp + feature_version` | 保单存续日、保费、保障额、免赔额、保障数、既往理赔次数/金额、近期变更次数 |
| `claim_risk_features` | `claim_id + prediction_timestamp + feature_version` | 客户/保单历史、产品/broker 时点特征、报告延迟、事故地区、提交时已知申报额 |

所有特征集必须有 `_run_id`,`feature_version`,`as_of_timestamp`,
`source_max_event_timestamp`。窗口聚合只接受业务时间严格早于
`prediction_timestamp` 的记录，并排除当前理赔。

## 12. V1 ML 目标与泄漏契约

V1 目标为 `high_risk_claim boolean`：在 `prediction_timestamp = submitted_at`
之后的观察窗口内，理赔最终成为高严重度或处于同产品类型/事故年度的高成本
分位区间。目标从未来合成结果稳定派生，但合成结果必须由多变量概率关系加
随机噪声产生；禁止用 `claim_amount > 固定阈值` 等单一确定规则直接造标签。

| 字段类别 | 示例 | ML 使用规则 |
|---|---|---|
| 预测时可用 | `claim_amount`,`incident_region`,`reporting_delay_days`, 提交时有效产品/保障 | 允许；源 `claimed_amount` 统一映射为 `claim_amount` |
| 预测前历史 | prior claims/payments/status changes、customer/policy tenure、历史 broker/product 指标 | 仅 `< prediction_timestamp` |
| 预测后结果 | `approved_amount`,`paid_amount`, final status/severity、investigation result、`settlement_days` | 只用于标签、BI、评估 |
| 潜在泄漏 | 无 as-of 的 lifetime/current 聚合、包含当前 claim 的 prior 指标、预测后快照 | 禁止 |

训练/验证/测试按 `prediction_timestamp` 做时间切分。V1 合成目标正例率建议
20%–35%，生成器使用固定种子，报告实际类平衡、关键分布和相关性，但不追求
完美可预测。

## 13. BI 与 ML 交叉使用契约

| 共享数据 | BI | ML |
|---|---|---|
| claim + product | 产品理赔频率、平均金额 | 预测前产品历史风险 |
| claim + region | 地区理赔金额/严重度 | 地区类别和历史地区风险 |
| policy + broker | broker 保费、赔付、损失率 | 预测前 broker 历史表现 |
| customer + policy + payment | 客户终身保费、续保、支付失败 | 客户存续期、历史保费、90 日失败次数 |
| status history | 状态漏斗、周转时间 | 预测前状态变化次数/间隔 |

## 14. 合成数据发布门禁

- 主从实体引用完整率 100%；孤儿记录为发布失败。
- 日期满足客户建立、保单生效、事故、报告、审批、支付、结案的业务顺序。
- 金额为现实的偏态/长尾分布，类别分布不允许全部均匀。
- 相关信号组合既往理赔、保单/客户存续期、产品、保障额、免赔额、地区、
  支付历史、保单变更和报告延迟，并加入受控噪声。
- 固定记录 random seed、generator version、场景参数、实际标签平衡和分布摘要。
- 单个输入字段不得完美决定 `high_risk_claim`；直接 PII 默认不得作为特征。
