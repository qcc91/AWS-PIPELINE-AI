# BI 与 ML 共享保险数据模型

## 1. 目标与实现边界

本模型以同一套保险业务事实同时支持传统 BI 和未来 ML 特征工程，不建立
ML 专用的平行业务数据源。当前 V1 已部署的 OLTP 核心实体是 customer、product、
policy、claim、payment；本轮正在把 product、broker、branch、claim type、region
risk、vehicle 和 coverage 文件主数据接入同一模型。真实 AWS 运行和 Gold 发布
完成前，文件扩展仍标记为“实施中”，不得宣称已经落地。

文件扩展复用现有 S3/EventBridge/Step Functions/Glue/Iceberg/Athena，不改
PostgreSQL OLTP，不引入 Feature Store、在线推理、持久 endpoint 或高级 MLOps。

## 2. 逻辑关系

```text
customer 1 ── n address
customer 1 ── n policy n ── 1 product
                         n ── 1 broker
policy   1 ── n policy_coverage
policy   1 ── n policy_status_history
policy   1 ── n claim 1 ── n claim_item
                      1 ── n claim_status_history
policy/claim 1 ── n payment
customer/policy/claim 1 ── n interaction_history
```

所有关系通过稳定业务键表达。历史表不覆盖旧记录，必须保存生效时间，以便
构建任意预测时点的可重现快照。

## 3. 共享实体

| 实体 | 主键 | 关键关系 | BI 用途 | ML 用途 |
|---|---|---|---|---|
| customer | `customer_id` | address、policy | 客户分群、留存、终身保费 | 客户存续期、历史理赔与渠道特征 |
| address | `address_id` | customer | 地域分布 | 预测时点地区类别；禁止精确地址特征 |
| product | `product_id` | policy | 产品组合、保费/赔付表现 | 产品类型、历史产品风险 |
| broker | `broker_id` | policy | 经纪人销售与损失率 | 截至预测时点的历史表现 |
| policy | `policy_id` | customer、product、broker | 在保量、续保、保费、保障额 | 保单存续期、免赔额、保障数量、变更频率 |
| policy_coverage | `policy_coverage_id` | policy | 保障组合、限额 | 预测时点有效保障与限额 |
| claim | `claim_id` | policy、customer | 理赔频率、金额、处理状态 | 提交时已知金额、报告延迟、历史上下文 |
| claim_item | `claim_item_id` | claim | 损失构成 | 提交时已知项目数量/类型/申报额 |
| payment | `payment_id` | policy 或 claim | 保费收入、赔付、失败支付 | 预测前支付失败、及时性和历史金额 |
| policy_status_history | 复合键 | policy | 状态迁移/流失 | 预测前变更次数和最近变更时间 |
| claim_status_history | 复合键 | claim | 处理漏斗、周转时间 | 仅预测前状态可作特征；后续状态用于标签 |
| interaction_history | `event_id` | customer/policy/claim | 渠道与交互趋势 | 预测前事件频率和渠道行为 |

## 4. 分层模型

### Bronze

按源实体保留原始记录、源时间、操作类型、run ID 和可重放元数据。Bronze
同样使用 Iceberg，不定义面向 BI 或 ML 的派生语义。

### Silver

Silver 保持业务可复用，不绑定特定报表或模型：

- `customer_current`, `address_current`, `product_current`, `broker_current`
- `policy_current`, `policy_coverage_current`, `claim_current`,
  `claim_item_current`, `payment_current`
- `policy_status_history`, `claim_status_history`, `interaction_history`
- `customer_claim_history` 作为按业务时间可过滤的历史关系视图

当前表保存最新状态；历史表至少包含 `valid_from`、`valid_to`、
`recorded_at`。构建时点数据时，不允许从当前表取一个在预测之后才更新的值。

### Gold BI

- `dim_customer`, `dim_product`, `dim_policy`, `dim_broker`, `dim_date`
- `fact_claim`, `fact_payment`, `fact_policy_transaction`
- `customer_360`, `policy_performance`, `broker_performance`
- `claim_daily_summary`

### Gold/ML 特征数据集

特征集仍由同一 Silver/Gold 事实派生：

- `customer_claim_features(customer_id, as_of_date, ...)`
- `policy_risk_features(policy_id, as_of_date, ...)`
- `claim_risk_features(claim_id, prediction_timestamp, ...)`

特征数据集必须保存 `feature_version`、`as_of_timestamp`、源数据截止时间和
生成 run ID。它们不是新的事实来源。

## 5. V1 ML 目标

预测问题：在理赔提交时点 `prediction_timestamp = submitted_at`，预测该理赔
是否最终成为高风险理赔。

`high_risk_claim` 定义为观察窗口内最终结果满足以下任一条件：

- 最终 `severity = HIGH`；或
- 最终 incurred amount 位于相同产品类型和事故年度合成总体的高成本分位区间。

标签由预测时点之后的合成结果生成。标签本身可以根据最终结果稳定计算，但
结果生成概率必须来自多变量组合加随机噪声，而不是单字段阈值。V1 合成样本
目标正例率为约 20%–35%，同时保留固定随机种子和实际生成分布报告。

## 6. 预测时点与泄漏边界

| 类别 | 字段/派生值 | 规则 |
|---|---|---|
| 提交时可用 | 申报金额、incident/report 时间、reporting delay、当前产品/保障、截至当时的保单与客户存续期 | 可以作为特征 |
| 提交前历史 | 既往 30/365 日理赔、既往支付失败、既往保单变更、历史 broker/product 指标 | 只聚合 `< prediction_timestamp` 的记录 |
| 结果字段 | final severity、approved/paid amount、最终状态、调查结果、settlement days | 只用于标签、BI 或预测后评估 |
| 高风险泄漏 | 无时间截点的 lifetime 汇总、当前快照状态、包含本次理赔的历史指标、预测后付款/状态 | 禁止进入训练特征 |

同一时间戳事件按稳定源顺序处理；窗口边界默认左闭右开并排除当前理赔。
Broker、产品和地区历史指标必须只使用在预测时点前已经结案并可见的数据。
训练/验证/测试优先按 `prediction_timestamp` 顺序切分，不能随机把未来结果
泄漏到过去。

## 7. 可复用特征契约

### customer_claim_features

`prior_claim_count_30d`, `prior_claim_count_365d`,
`prior_claim_amount_365d`, `active_policy_count`, `customer_tenure_days`,
`payment_failure_count_90d`, `preferred_channel`, `region`。

### policy_risk_features

`policy_tenure_days`, `premium_amount`, `sum_insured`, `deductible_amount`,
`coverage_count`, `prior_claim_count`, `prior_claim_amount`,
`recent_policy_change_count`, `payment_frequency`, `product_type`。

### claim_risk_features

组合客户、保单、产品和 broker 的时点特征，并增加 `reporting_delay_days`,
`incident_region`, `claim_type`, `claim_amount`, `claim_item_count`。源字段
`claimed_amount` 在 Silver 统一为现有契约名 `claim_amount`。输出标签列
`high_risk_claim` 只在训练数据集中出现。

## 8. BI 与 ML 交叉复用

| 共享事实 | BI 指标 | ML 特征 |
|---|---|---|
| claim + product | 产品理赔频率/平均金额 | 预测前产品历史频率和成本 |
| claim + region | 地区理赔金额与严重度 | incident region 类别、历史地区风险 |
| policy + broker | broker 保费、赔付、损失率 | 预测前 broker 历史表现 |
| customer + policy + payment | 客户终身保费、续保、失败支付 | 客户存续期、历史保费、90 日失败次数 |
| status history | 状态漏斗与处理时间 | 最近保单变更和预测前状态迁移次数 |

## 9. 合成数据原则

- 固定并记录随机种子、生成器版本和场景参数。
- 先生成主实体，再按外键生成从实体，发布前校验引用完整性。
- 日期顺序满足客户建立、保单生效、事故、报告、审批、支付和结案的业务顺序。
- 金额使用偏态/长尾分布；类别使用不均匀但可解释的分布。
- 潜在风险概率可组合历史理赔、报告延迟、存续期、产品、保障额、免赔额、
  地区、支付历史和保单变更，再加入噪声后抽样结果。
- 任何一个输入字段都不能单独、完美决定标签；需报告类平衡和关键相关性。
- 直接 PII 只用于业务真实性和受控联接，不作为默认 ML 特征。

## 10. 文件参考模型与 V1 映射

```text
FILE broker_claims -> OLTP policy/customer -> OLTP product_id
                   -> FILE product_master
                   -> FILE broker_master -> branch_master
                   -> FILE claim_type/region/vehicle/coverage reference
                   -> Gold fact_claim_enriched
```

这一 V1 路径不向 RDS 增列。外部 broker claim 文件携带现有 policy/customer
业务键和 broker/claim-type/region/vehicle/coverage 参考键；产品键由 OLTP policy
取得。文件理赔是 Batch 来源自身的事实，不复制或覆盖 OLTP claim。Gold 必须
携带来源并通过引用完整性门禁。完整字段、外键和版本规则见
`architecture/data-contracts.md`。

文件维度的已实现 Gold 模型为 `dim_product_master`,`dim_broker`,`dim_branch`,
`dim_claim_type`,`dim_region_risk`,`dim_vehicle`,`dim_coverage`；统一跨源事实为
`fact_claim_enriched`，并提供 `policy_performance`,`broker_performance` 和
`claim_risk_features`。这些对象已于 2026-09-10 在 DEV 真实跑通。

## 11. 文件衍生特征的时点规则

- Product 选择 `effective_from <= prediction_timestamp` 的最新有效版本；有
  effective_to 时还必须满足 prediction_timestamp 小于 effective_to。
- Broker、region 和其他 reference 只选择 `source_updated_at` 不晚于预测时点的
  最新文件批次。
- Vehicle/coverage 在 V1 为有版本的静态批次；只允许使用在预测时点前已发布
  的批次。`vehicle_age` 由 manufacture_year 和 prediction_timestamp 推导。
- Broker/product/region 的历史损失率和理赔频率不是文件原值；只能从预测时点
  前已结案且当时已可见的 Gold 事实计算。
- `severity_group`、`risk_category` 等参考分类不能替代结果标签；final severity、
  approved/paid amount 和最终状态依然禁止进入特征矩阵。
