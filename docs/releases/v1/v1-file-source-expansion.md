# V1 文件源扩展运行与验收清单

## 范围与当前状态

本包复用现有 CSV → S3 Landing → EventBridge → Step Functions → Glue →
Bronze/Silver/Gold Iceberg → Athena 路径，不修改 PostgreSQL OLTP，不新增持续
计费服务，不订阅 QuickSight，不运行配额仍为零的 SageMaker，也不开始 V2。

当前状态：**COMPLETE**。2026-09-10 已在 `ap-southeast-2` 完成真实
Landing、EventBridge、Step Functions、Glue、Iceberg 和 Athena 验证。

## 数据发布检查

- [x] 固定种子生成 7 个主参考 CSV 和扩展 broker claim CSV，记录实际行数和内容摘要。
- [x] 所有主键唯一，broker claim 的 policy/customer/参考键引用完整率为 100%。
- [x] 目标行数：broker claims 120、product 30、broker 80、branch 20、claim type 16、region 40、
  vehicle 500、coverage 20；差异必须说明。
- [x] 文件不含真实 PII、凭据、token、Terraform state 或 plan。
- [x] 产品 `product_id` 与实际 OLTP policy.product_id 的覆盖情况已量化；未匹配
  记录被解释而不是静默删除。

## 真实 AWS 路径

- [x] 每个文件上传到批准的 Landing prefix。
- [x] EventBridge 规则捕获对象事件，Step Functions 执行成功。
- [x] Glue 运行成功，7 个 Bronze 和 7 个 Silver Iceberg 表行数正确。
- [x] Gold 维表与 `fact_claim_enriched` 发布成功且无重复 claim_id。
- [x] Terraform/state 无非预期 drift；没有 destroy 或新持续计费资源。

## Athena 跨源证明

- [x] policy + product_master。
- [x] policy + product_master + broker + branch。
- [x] claim + product_master + claim type。
- [x] claim + product_master + region risk。
- [x] claim + product_master + coverage reference。
- [x] motor claim + product_master + vehicle reference。
- [x] 业务查询至少覆盖产品保费、active policy by broker、broker region、claim
  category、region risk、product/broker loss ratio、motor vehicle risk。
- [x] 保存实际 SQL、query execution ID、返回行和扫描量/成本摘要。

## ML readiness

- [x] `claim_risk_features` 候选联接获得 product/broker/region/vehicle/coverage
  字段，并报告非空率、范围和类别分布。
- [x] effective-date/as-of 条件以 claim submitted_at 为准。
- [x] 当前 claim 和预测后 approved/paid/final status/severity/settlement 字段未
  进入特征。
- [x] 未在 quota 为零时启动 SageMaker training 或 transform job。

## 完成记录

实际行数与本页目标完全一致。Bronze/Silver 分别为 product 30、broker 80、
branch 20、claim type 16、region 40、vehicle 500、coverage 20，扩展 claim 为
120；Gold `fact_claim_enriched` 和 `claim_risk_features` 各 120，
`policy_performance` 和 `broker_performance` 各 3。跨源缺失计数全部为 0。

Athena 证据：行数 `572abf19-71da-4fa1-a9cf-39cf8b897cfc`，联接完整性
`192fe53f-3fe5-444f-b0bf-e6300f37100b`，产品指标
`cb7f11d4-30e3-4e75-a848-cf721c50b6b0`，broker 指标
`b1711479-e983-4650-8057-cd2c2252f8b2`，claim/region
`545a2cac-4b83-4973-99ad-e347080e47a6`，motor
`8078429a-0390-476a-80a1-d4d6e8877777`，ML readiness
`236fe73c-e1de-4c84-be01-dd008d412bac`。时点修正后的最终 as-of 检查
`e98e80f0-afb7-41ad-beb7-63f133deac39` 返回 120 行，所有 future-reference
计数均为 0。

Terraform 实际变化为 `0 add / 1 change / 0 destroy`，仅原位更新现有 Glue
脚本 S3 对象；随后定向刷新计划为 no changes。一次 product 触发在 Glue 并发
槽释放前失败，错误为 `ConcurrentRunsExceededException`，等待并重投后成功，
无需配置或架构变更。首次发布的 8 个成功 Glue Run 合计 1,334 DPU-seconds，
按本项目 $0.44/DPU-hour 估算约 USD 0.16；时点修正重跑产生同量级一次性费用，
Athena/S3/EventBridge/Step Functions 增量为不足一美分量级，无新增固定月费。

本地测试为 39 passed；CSV 还通过 Artifact Tool 逐文件解析检查。Git commit 和
origin/main push 结果以仓库提交历史为准。

## 已知数据限制

为遵守“本包不修改 RDS”的边界，120 条外部 broker claim 只引用现有 OLTP 的
3 张保单和 3 个客户。产品及 broker 维度的保费只按保单计算一次，技术上避免了
因多条理赔重复累加保费；但以如此少的保单承载 120 条合成理赔会产生异常偏高的
loss ratio。因此这些指标只证明跨源联接、聚合和查询可运行，不能作为真实保险
业务表现或模型效果基准。后续若扩大业务样本，应通过新的获批包扩展源数据，而不
在本包中隐式修改 PostgreSQL。
