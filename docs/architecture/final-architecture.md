# V5 最终架构

本图描述已验收版本 `v5.0-production-ready`（`5e0b479`）的实现边界。结构化数据平台运行于 DEV；完整 PROD 平台未部署。实线表示数据或执行路径，虚线表示共享治理、监控或未来接入。

```mermaid
flowchart TB
  subgraph sources[Structured sources]
    CSV[Batch CSV and reference files]
    PG[RDS PostgreSQL] --> DMS[DMS full load and CDC]
  end
  subgraph lake[DEV Lakehouse]
    LAND[S3 Landing CSV] --> EVT[EventBridge]
    EVT --> SF[Step Functions]
    SF --> GLUE[Glue stage jobs and DQ gates]
    GLUE --> B[Bronze Iceberg]
    B --> S[Silver Iceberg]
    S --> G[Gold Iceberg]
    GOV[Glue Catalog and Lake Formation]
    GOV -.-> B
    GOV -.-> S
    GOV -.-> G
  end
  CSV --> LAND
  DMS --> LAND
  subgraph consumers[Analytics and batch ML]
    A[Athena]
    ML[SageMaker XGBoost and Batch Transform]
    P[Glue prediction publication]
    QS[QuickSight deferred]
    A -.-> QS
    ML --> P
  end
  G --> A
  G -->|submission-time features| ML
  P -->|claim_risk| G
  subgraph rag[Document RAG]
    DOC[S3 approved documents] --> KB[Bedrock Knowledge Base]
    KB --> TITAN[Titan Embeddings V2]
    TITAN --> VEC[S3 Vectors]
    VEC -->|retrieval| NOVA[Nova Micro and citations]
  end
  subgraph controls[Shared operational controls]
    AUD[Quarantine and run audit]
    MON[CloudWatch and EventBridge alerts] --> SNS[Encrypted SNS]
    SEC[IAM / KMS / Secrets Manager / CloudTrail]
  end
  GLUE -.-> AUD
  SF -.-> MON
  GLUE -.-> MON
  DMS -.-> MON
  SEC -.-> lake
  SEC -.-> rag
  subgraph delivery[Delivery proof only]
    GH[GitHub and Actions] --> CD[CodePipeline and CodeBuild]
    CD --> DP[DEV proof Log Group]
    DP --> HA[Human approval]
    HA --> PP[Minimal PROD proof Log Group]
  end
  classDef data fill:#e8f1ff,stroke:#3569a8,color:#172b4d;
  classDef process fill:#e7f5ef,stroke:#398268,color:#173f32;
  classDef control fill:#fff4d6,stroke:#ab8124,color:#594410;
  classDef deferred fill:#f1f1f1,stroke:#777,color:#444,stroke-dasharray:5 5;
  class CSV,PG,LAND,B,S,G,DOC,VEC,DP,PP data;
  class DMS,EVT,SF,GLUE,A,ML,P,KB,TITAN,NOVA,GH,CD process;
  class GOV,AUD,MON,SNS,SEC,HA control;
  class QS deferred;
```

Bronze、Silver、Gold 均为 S3 上的 Iceberg 表，由 Glue 分阶段处理。图中的层间箭头表示处理依赖；每一步仍由 Glue 执行。Batch 理赔与 PostgreSQL 理赔保留不同事实表，外部文件不会覆盖 OLTP 事实来源。

ML 正式特征排除赔付金额、最终状态等事后字段，运行短时训练与批量推理，预测结果回写 Gold。验收使用日期早于理赔提交的单一参考快照；未实现多版本参考数据的 as-of join。RAG 的实际输入是独立的获批文档：没有已实现的 Gold → Knowledge Base 自动同步。图中向量检索与回答为概念路径，由应用调用 Bedrock 完成。

Delivery 子图仅表示独立 proof stack 的发布顺序；它不连接或部署完整 DEV Lakehouse。人工审批后的 PROD 范围仍只有一个 proof 日志组。

成本边界：AWS FREE 计划保持不变；QuickSight 未订阅；无持久 SageMaker endpoint、OpenSearch 或替代流式系统。Streaming 自 V2 起退役，不是等待启用的活动组件。既有 DMS 任务失败状态与保留历史重放证明需分开理解；SNS 已验证服务投递，但未配置人工订阅。

交付控制面见 [CI/CD 与安全边界](cicd-security.md)，处理语义见 [数据流](data-flow.md)。实现及验证依据：[V5 完成评审](../releases/v5/v5-completion-review.md)、[运行证据](../releases/v5/v5-runtime-evidence.md)、[ML 结果](../releases/v1/v1-ml-result.md)、[RAG](../releases/v1/v1-rag.md)。历史评审中“等待验收”的文字记录其当时状态，最终版本以验收标签为准。
