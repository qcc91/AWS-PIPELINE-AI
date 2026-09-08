# ADR-002：使用 AWS Step Functions 编排

- 状态：Accepted — Gate 1 于 2026-09-08 批准

## Context

批量、CDC 微批和流落地处理需要统一运行 ID、有界重试、DQ 门禁、失败处理、对账和可见执行历史。

## Decision

使用 EventBridge 触发 Step Functions，编排 Glue 和控制步骤。默认瞬态失败最多 3 次指数退避；验证失败不重试。终止失败写审计、CloudWatch 指标并按影响通过 SNS 告警。Standard 与 Express 类型在频率/历史需求实测后选择。

## Alternatives

- 仅 EventBridge + Glue workflow：部分场景可用，但跨服务错误分支和显式状态表达较弱。
- 自建调度器/Airflow：引入运行维护和持续成本，对小规模不合理。

## Reason

托管状态机直接表达幂等步骤、失败路径和门禁，减少自定义控制平面。

## Cost Impact

按状态转换/执行计费；通过适度粒度和批量触发控制，不创建常驻编排计算。

## Consequences

每个 task 必须有 timeout、retry 分类、catch 和幂等契约；避免状态 payload 携带数据/PII，只传 URI 和标识。
