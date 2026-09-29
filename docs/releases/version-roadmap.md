# V1–V6B 已验收路线图

工程实施已完成至 V6B。V6B 是 V6 托管 ML 平台的增强并与 V6 共用最终发布标签；各版本在同一代码库累计演进，详细视觉导航见[演进图](../architecture/evolution.md)。

| 版本 | 实际交付 | 发布标签 |
|---|---|---|
| V1 | DEV Batch/CDC、三层 Iceberg、Athena、XGBoost batch ML、文档 RAG；QuickSight 延后，Streaming 受账户限制 | v1.0-happy-path |
| V2 | 分阶段重试、幂等、隔离、对账、重放、自定义 DQ + Glue DQDL；Streaming 退役 | v2.0-reliable |
| V3 | MFA 与角色链、persona/Lake Formation/PII 控制、KMS/S3/Secrets、CloudTrail、ALLOW/DENY | v3.0-governed |
| V4 | 全仓库 PR CI、protected main、CodePipeline/CodeBuild、DEV/PROD 最小 proof、精确计划人工审批 | v4.0-cicd |
| V5 | 四个告警、SNS 发布、受控失败/恢复、Batch/CDC 重放、类型/DQ 修复、安全回归、运行手册 | v5.0-production-ready |
| V6 | 原生 SageMaker Pipeline：准备数据、训练、评估、质量门禁、Model Registry、Batch Transform、Gold 发布 | v6.0-sagemaker-ml-platform（最终收口后创建） |
| V6B | 离线 Feature Store 物化/读回、Unified Studio Managed MLflow 实验与真实运行证据；DEV-only | 与 V6 共用标签 |

[各版本完成证据](../README.md)保留实施历史。V5 的 production-ready 标签表示小规模作品集范围的运维验收，不代表完整 PROD 平台、业务 SLA 或模型业务上线。

V6B Small MLflow 首次验证运行约 14 小时 52 分钟，超过批准的 4 小时窗口，估算约 USD 9.55；服务器已停止，DEV 策略为不用即停止。V6/V6B 没有 endpoint、在线 Feature Store 或 PROD ML 部署。

本次最终文档收口不构成新版本授权。任何新的生产部署仍需 Human 对具体计划批准；不得自动开始 V7。
