# ADR-005：欺诈预测使用批量推理

- 状态：Accepted — Gate 1 于 2026-09-08 批准

## Context

初始 ML 用例是小数据量 claim fraud prediction，没有获批的毫秒级在线评分 SLA。持久 endpoint 会产生闲置成本并扩大运维/安全面。

## Decision

用 SageMaker Processing 构建特征、XGBoost Training 训练、Evaluation 门禁、Model Registry 管理版本，并用 Batch Transform 批量推理。结果按 `claim_id + model_version` 写入 Gold `claim_risk`，供 Athena/BI 复用。

## Alternatives

- Persistent real-time endpoint：低延迟，但当前无需求且持续计费。
- Serverless/async endpoint：若未来有近实时需求可评估，当前仍增加在线 API 生命周期。
- Glue 内直接加载模型：可能便宜，但削弱模型治理和可追溯性。

## Reason

批量模式与 Gold 刷新节奏、成本原则和现有平台自然结合，同时保留训练/模型治理。

## Cost Impact

仅在 processing/training/transform 运行时计费；设置 timeout、并发和 artifact lifecycle。不支付空闲 endpoint。

## Consequences

预测不是实时；必须记录数据快照、模型版本、时间和评估结果。未来实时需求须提交 SLA、成本、安全和回滚 ADR。
