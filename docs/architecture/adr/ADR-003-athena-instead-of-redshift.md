# ADR-003：Athena 替代 Provisioned Redshift

- 状态：Accepted — Gate 1 于 2026-09-08 批准

## Context

Gold 数据量小、查询以演示和周期性 BI 为主，不需要常驻 MPP 仓库。

## Decision

Athena 直接查询 Gold Iceberg；QuickSight 通过受控 Athena workgroup 访问。使用列式压缩、业务日期分区、结果加密和扫描限制。

## Alternatives

- Redshift provisioned：成熟仓库能力，但空闲成本与运维不符合当前规模。
- Redshift Serverless：可按需，但在本阶段仍增加数据复制/治理面，收益未证明。

## Reason

Athena 与 S3/Iceberg/Catalog 原生结合，按扫描付费且无常驻集群，是当前规模的最小架构。

## Cost Impact

主要成本为扫描量和 QuickSight；通过分区、压缩、Gold 预聚合和 workgroup limits 控制。

## Consequences

交互延迟和高并发能力有限；如实测 SLA 不满足，须提交新 ADR 和成本比较，不能直接增加仓库。
