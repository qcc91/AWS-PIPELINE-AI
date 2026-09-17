# ADR-004：Bedrock Knowledge Bases 使用 S3 Vectors

- 状态：Accepted — Gate 1 于 2026-09-08 批准

## Context

首版 RAG 面向少量保险政策、理赔指南、产品文档和 FAQ，需要来源引用和低运维成本，不需要复杂检索集群。

## Decision

文档保存在受治理 S3 文档区，Bedrock Knowledge Bases 负责 ingestion/chunk/embed，S3 Vectors 作为 vector store。每个 KB 使用独立 index，首版采用 semantic search，并通过 Retrieve/RetrieveAndGenerate 保留来源引用。

## Alternatives

- OpenSearch Serverless：支持 hybrid/高级检索，但当前需求不值得增加最低持续成本和复杂度。
- 自建向量数据库：增加计算、补丁、备份和访问治理。
- 手工 embeddings/search：灵活但重复实现托管 KB 能力。

## Reason

与批准架构一致，托管集成少，S3 Vectors 更偏存储成本优化，满足首版语义检索。

## Cost Impact

按文档 ingestion、embedding、vector storage/query 和生成 token 计量；通过小语料、增量同步、评估限额控制。区域/模型/配额部署前复核。

## Consequences

接受 semantic-only 及 metadata 限制；需要 hybrid search/高 QPS 时走架构审批。必须测试访问过滤、删除同步、引用正确性、忠实度、提示注入和拒答。

参考：[AWS S3 Vectors 与 Bedrock Knowledge Bases](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html)
