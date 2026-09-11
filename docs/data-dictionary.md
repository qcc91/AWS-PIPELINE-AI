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

## V3 实际表 PII 索引

等级含义：`HIGH` 为直接身份信息、DOB 或可能包含 PII 的自由文本；`MEDIUM`
为可回连个人的稳定标识或保密业务度量；`LOW` 为非个人参考/聚合/技术元数据。
表级等级取其最高列等级。

| 当前 Glue/Iceberg 表 | PII | 表级 | PII/敏感列 | 最小消费者 |
|---|---|---|---|---|
| Bronze/Silver `customers_cdc` / `customers` | YES | HIGH | HIGH: `first_name,last_name,date_of_birth,email,phone`; MEDIUM: `customer_id` | DataEngineer |
| Bronze/Silver `policies_cdc` / `policies` | YES | MEDIUM | `policy_number,customer_id,policy_id`; 金额为 MEDIUM/非 PII | DataEngineer |
| Bronze/Silver `claims_cdc` / `claims` | YES | HIGH | HIGH: `description`; MEDIUM: `claim_number,customer_id,policy_id,claim_id` 与金额/结果 | DataEngineer |
| Bronze/Silver `payments_cdc` / `payments` | YES | MEDIUM | `provider_reference,claim_id,policy_id,payment_id`; 金额为 MEDIUM/非 PII | DataEngineer |
| Bronze/Silver `claim`（broker 文件） | YES | HIGH | `description`; `claim_number,customer_id,policy_id,claim_id` | DataEngineer |
| Bronze/Silver `products_cdc` / `products` | NO | LOW | 无 | DataEngineer |
| Bronze/Silver 七个 file reference/master 表 | NO | LOW | `broker_name` 为虚构企业名；region 只到合成区域/城市 | DataEngineer |
| Gold `fact_claim`,`fact_claim_cdc`,`fact_claim_enriched` | YES | MEDIUM | `claim_number,customer_id,policy_id,claim_id`; description 已移除；金额/结果为 MEDIUM/非 PII | DataEngineer；Analyst 仅列授权 |
| Gold `policy_performance` | YES | MEDIUM | `policy_id`；金额/损失率为 MEDIUM/非 PII | DataEngineer；Analyst 仅列授权 |
| Gold `claim_risk_features`,`claim_risk` | YES | MEDIUM | `claim_id` 为间接 PII；标签、概率为 MEDIUM/非 PII | DataEngineer、MLEngineer；Analyst 可读 `claim_risk` 批准列 |
| Gold `claim_daily_summary`,`claim_daily_summary_cdc`,`broker_performance` | NO | LOW | 聚合数据；当前小样本 DEV 仍避免对外发布小单元 | DataEngineer、Analyst |
| Gold `dim_product_master`,`dim_broker`,`dim_branch`,`dim_claim_type`,`dim_region_risk`,`dim_vehicle`,`dim_coverage` | NO | LOW | 参考/虚构企业属性 | DataEngineer、Analyst |
| control run/DQ audit | NO | LOW | `error_message` 必须脱敏；不得嵌入原记录 | DataEngineer |
| quarantine JSON | YES | HIGH | `source_record`/`original_record` 继承源记录最高等级 | 获批 DataEngineer 调查职责 |

Analyst 不获得任何 Landing/Bronze/Silver/quarantine 权限。MLEngineer 的最小
范围仅为 Gold `claim_risk_features` 和 `claim_risk`，不因“可能有用”获得通用
Silver 访问。完整执行矩阵和正反验证见 `docs/v3-data-governance.md`。
