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
| `claim_risk` | claim + model_version | ML/BI | 概率 `[0,1]`，模型版本必填 |

`claim_risk` 最小字段：`claim_id`, `fraud_probability decimal(6,5)`, `risk_level LOW|MEDIUM|HIGH`, `model_version`, `prediction_timestamp`, `_run_id`。风险阈值必须由模型评估/业务批准，不能在契约中随意固定。

## 10. 审计与隔离契约

审计记录：`run_id,pipeline_name,source,stage,status,start_time,end_time,input_count,output_count,rejected_count,duplicate_count,quality_score,error_code,error_message`。错误消息必须脱敏且有长度限制。

隔离记录：`quarantine_id,run_id,source_object,entity,error_category,error_code,error_reason,quarantined_at,schema_version,original_record`。`original_record` 加密且仅限调查角色；不得静默删除。保留期由数据治理批准。
