# 数据字典

本字典是 `architecture/data-contracts.md` 的可读索引。字段精确类型、允许值和
发布门禁以数据契约为准。`已实现` 表示当前 V1 核心路径已有对应数据；
`设计` 表示共享 BI/ML 扩展契约，尚未授权部署。

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
| interaction_history | Streaming 设计就绪、账号阻塞 | event | type、source、channel、business IDs | event_timestamp | payload 禁止无必要 PII | 渠道趋势和预测前行为 |
| customer_claim_features | 设计 | customer + as_of | 30/365 日理赔、保单数、存续期、支付失败 | as_of_timestamp | 默认无直接 PII | ML 共享特征 |
| policy_risk_features | 设计 | policy + as_of | 存续期、保费、保障额、免赔额、历史理赔/变更 | as_of_timestamp | 无 | ML 共享特征 |
| claim_risk_features | 设计 | claim + prediction time | 客户/保单/产品/broker 历史、报告延迟、申报额 | prediction_timestamp | 默认无直接 PII | XGBoost 训练/推理 |
| claim_risk | 已有输出契约 | claim + model version | high-risk probability、risk level、model version | prediction_timestamp | 无 | ML 输出与 BI 展示 |

统一金额字段使用 `decimal(18,2)` 和 ISO 4217 currency；时间戳使用 UTC。
历史聚合必须保存 `as_of_timestamp`，并只读取严格早于预测时点的数据。
