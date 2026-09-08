# ADR-001：Bronze、Silver、Gold 使用 Apache Iceberg

- 状态：Accepted — Gate 1 于 2026-09-08 批准

## Context

三类来源包含重复、CDC 更新/删除、迟到事件和重跑。三层都需要审计、一致读写和可恢复变更；仅用散落 Parquet 文件会把 MERGE、并发与快照逻辑转移到自定义代码。

## Decision

Bronze、Silver、Gold 全部采用 Amazon S3 上的 Apache Iceberg，并使用 Glue Data Catalog。Landing 保留原始 CSV/DMS/Firehose 对象，不属于 Iceberg 层。Glue 负责写入/MERGE；Athena 通过 Catalog 查询。表维护包括小文件治理、快照过期和孤儿文件清理，保留期需先批准。

## Alternatives

- 纯 Parquet：便宜简单，但 CDC/current-state、原子提交和 schema 演进风险高。
- Delta/Hudi：技术可行，但与当前 AWS Glue/Athena 设计相比没有足够收益，增加格式分歧。
- 数据仓库：对小数据量增加持续成本和复制架构。

## Reason

统一表格式降低跨层实现差异，提供 ACID、快照和 MERGE，支持可重放/审计的 CDC 管道。

## Cost Impact

不新增常驻服务；增加 Glue 维护作业和快照/S3 存储。通过批处理、压缩和保留策略控制。

## Consequences

团队必须管理并发提交、分区、small files、snapshot retention 和兼容版本；消费者通过 Catalog 而非物理文件路径读表。
