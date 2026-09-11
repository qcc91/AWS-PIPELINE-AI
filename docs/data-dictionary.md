# 数据字典

本字典是 `architecture/data-contracts.md` 的可读索引。字段精确类型、允许值和
发布门禁以数据契约为准。`已实现` 表示当前 V1 核心路径已有对应数据；
`设计` 表示后续共享 BI/ML 扩展契约；当前文件扩展相关的 `已实现` 数据集均已
完成真实 AWS 验证。

| 实体/数据集 | 状态 | 主键/粒度 | 重要业务字段 | 时间字段 | PII | BI/ML 用途 |
|---|---|---|---|---|---|---|
| customer | 已实现；待扩展 | customer | DOB/age band、region、segment、household、channel | customer_since、created/updated | 姓名、DOB、联系信息 | 分群、存续期、历史行为 |
| address | 设计 | address | customer、region、postal area、type | valid_from/to | 完整地址 | 地域 BI；ML 仅粗粒度地区 |
| product | 已实现；待扩展 | product | code、type、status | effective_from/to | 无 | 产品表现、产品类别特征 |
| broker | 设计 | broker | branch、region、commission、active | valid_from/to | 低 | broker 表现和历史特征 |
| policy | 已实现；待扩展 | policy | product、broker、premium、sum insured、deductible、coverage count、frequency | start、renewal、end、created/updated | policy number | 保费/续保 BI、风险特征 |
| policy_coverage | 设计 | coverage | policy、coverage type、limit、deductible、active | effective_from/to | 无 | 保障组合和时点保障特征 |
| claim | 已实现；待扩展 | claim | type、claimed/approved/paid、status、severity、region | incident、reported、submitted、closed | number、description | 理赔 BI、提交时风险预测 |
| claim_item | 设计 | claim item | type、claimed/approved amount、status | created/updated | 描述可能敏感 | 损失构成和申报项目特征 |
| payment | 已实现；待扩展 | payment | type、amount、status、method | payment timestamp | provider reference | 收支 BI、历史失败支付特征 |
| policy_status_history | 设计 | policy + change time + sequence | previous/new status、reason | status_change_time | 无 | 状态迁移、变更频率 |
| claim_status_history | 设计 | claim + change time + sequence | previous/new status、reason | status_change_time | 无 | 漏斗/时效；预测后状态禁作特征 |
| interaction_history | 业务概念保留；无流式入口 | event | type、source、channel、business IDs | event_timestamp | payload 禁止无必要 PII | 仅可经 Batch/CDC 提供渠道趋势和预测前行为 |
| customer_claim_features | 设计 | customer + as_of | 30/365 日理赔、保单数、存续期、支付失败 | as_of_timestamp | 默认无直接 PII | ML 共享特征 |
| policy_risk_features | 设计 | policy + as_of | 存续期、保费、保障额、免赔额、历史理赔/变更 | as_of_timestamp | 无 | ML 共享特征 |
| claim_risk_features | V1 已实现；V2 已增加验证与版本 | claim_id | 产品、broker、地区风险、vehicle、coverage、申报额和监督标签 | submitted_at/reference snapshot | 默认无直接 PII | XGBoost 训练/推理与可追溯重处理 |
| claim_risk | 已有输出契约 | claim + model version | high-risk probability、risk level、model version | prediction_timestamp | 无 | ML 输出与 BI 展示 |
| broker_claims 文件 | 已实现 | claim_id | OLTP policy/customer 键、broker/claim type/region/coverage/vehicle 键、金额、状态、结果标签 | incident/submitted/updated | claim number/description 为虚构值 | Batch 理赔事实、跨源丰富化和 ML readiness |
| product_master 文件 | 已实现 | product_id | type/status、base premium、risk/underwriting、channel、max sum insured | effective_from/to、source updated | 无 | 连接 OLTP product/policy；产品 BI/ML 属性 |
| broker_master 文件 | 已实现 | broker_id | branch、commission、experience、tier、status | effective/source updated | broker name 为虚构企业展示值 | broker/branch BI、未来历史特征 |
| branch_master 文件 | 已实现 | branch_id | region、state、city、status | source_updated_at | 无 | 组织与区域分析 |
| claim_type_reference 文件 | 已实现 | claim_type_id | code/name、product type、category/severity、resolution days、risk threshold | source_updated_at | 无 | claim category BI、提交时分类特征 |
| region_risk_reference 文件 | 已实现 | region_code | state、accident/theft/weather/natural-hazard/catastrophe score、risk band | effective/source updated | 无精确地址 | 区域 BI、外部风险特征 |
| vehicle_reference 文件 | 已实现 | vehicle_code | make/model/year/class/value/safety/theft/repair/risk | source_updated_at | 无 VIN/登记信息 | motor BI、车辆年龄/风险特征 |
| coverage_reference 文件 | 已实现 | coverage_code | name/product type/category/deductible/limit/tier | source_updated_at | 无 | 保障分析与提交时已知特征 |
| fact_claim_enriched | 已实现 | claim_id | broker claim + OLTP policy/customer/product + 7类文件参考属性 | claim submitted + reference version | 无新增真实 PII | 跨源 BI 证明和 claim_risk_features 输入 |

统一金额字段使用 `decimal(18,2)` 和 ISO 4217 currency；时间戳使用 UTC。
历史聚合必须保存 `as_of_timestamp`，并只读取严格早于预测时点的数据。
当前 RDS 不含 broker、region、coverage、vehicle、claim type 交易外键；V1 由
外部 broker claim 文件携带这些参考键，policy/customer 继续引用 OLTP。该文件
来源不覆盖 PostgreSQL claim 表。
