# 命名标准

## 1. 通用规则

- 逻辑名称使用小写 ASCII；单词以 `-` 分隔资源名，以 `_` 分隔表、列和代码标识符。
- AWS 资源基础模式：`insurance-{env}-{region_or_scope}-{component}-{purpose}`；受长度/字符限制时保留 `insurance`、环境、组件和用途。
- 环境仅允许 `dev`、`prod`。region 使用 AWS 标准代码，如 `ap-southeast-2`，不得写 `au` 之类自定义缩写。
- 项目默认 region 固定为 `ap-southeast-2`；region 不得由隐式 provider fallback 决定。
- 名称不得包含人员姓名、秘密、账号 ID、客户 PII 或临时工单号。
- 全局唯一资源（如 S3 bucket）增加稳定、非敏感的组织/账号短标识；不得随机到无法辨认。
- 资源 tag 至少含 `Project=aws-insurance-data-ai`、`Environment`、`Owner`、`ManagedBy=terraform`、`CostCenter`、`DataClassification`。

## 2. 示例

| 对象 | 模式 | DEV 示例 |
|---|---|---|
| S3 bucket | `{org}-insurance-{env}-{purpose}-{account_short}` | `acme-insurance-dev-lake-1234` |
| KMS alias | `alias/insurance/{env}/{purpose}` | `alias/insurance/dev/data` |
| IAM role | `insurance-{env}-{component}-{purpose}-role` | `insurance-dev-glue-silver-role` |
| Glue database | `insurance_{env}_{layer}` | `insurance_dev_bronze` |
| Glue job | `insurance-{env}-{layer}-{entity}` | `insurance-dev-silver-claim` |
| Step Functions | `insurance-{env}-{pipeline}-sfn` | `insurance-dev-claim-batch-sfn` |
| DMS task | `insurance-{env}-{source}-{mode}` | `insurance-dev-oltp-full-cdc` |
| Kinesis stream | `insurance-{env}-{domain}-events` | `insurance-dev-policy-events` |
| SNS topic | `insurance-{env}-{severity}-alerts` | `insurance-dev-critical-alerts` |
| Secret | `insurance/{env}/{system}/{credential}` | `insurance/dev/postgres/dms` |
| CloudWatch log group | `/insurance/{env}/{service}/{component}` | `/insurance/dev/glue/silver-claim` |

示例中的 `acme` 与 `1234` 是占位符，不得直接实施。

## 3. S3 键与数据层

```text
landing/source={source}/entity={entity}/ingest_date={yyyy-mm-dd}/run_id={uuid}/
bronze/{entity}/               # Iceberg 表 location，由 catalog 管理
silver/{entity}/               # Iceberg 表 location
gold/{dataset}/                # Iceberg 表 location
quarantine/{category}/source={source}/entity={entity}/ingest_date={date}/run_id={uuid}/
documents/domain={domain}/classification={class}/document_id={id}/version={version}/
```

Landing、quarantine 可使用 hive-style 前缀方便调查；Iceberg 消费者必须通过 Catalog 表访问，不依赖物理对象文件名。Bronze、Silver、Gold 全部使用 Iceberg。

## 4. 表、列和标识符

- 表名为单数实体或明确数据集：`claim`、`dim_customer`、`fact_payment`、`claim_daily_summary`。
- 技术元数据使用 `_` 前缀：`_run_id`、`_ingested_at`、`_record_hash`、`_source_system`。
- 主键为 `{entity}_id`；时间点后缀 `_at`，日期后缀 `_date`，金额后缀 `_amount`，布尔值以 `is_`/`has_` 开头。
- 金额必须配对 `currency_code`；状态字段后缀 `_status`。
- `run_id`、`event_id` 使用 UUID/ULID 等稳定全局标识；具体格式一经契约发布不得任意改变。

## 5. 代码、Git 与 CI

- Python 模块/函数：`snake_case`；类：`PascalCase`；常量：`UPPER_SNAKE_CASE`。
- Terraform resource label 和变量：`snake_case`；module 目录：`kebab-case` 或既定模块名，仓库内保持一致。
- 分支默认：`codex/{type}/{short-description}`；人工团队可使用获批前缀，禁止把环境名当长期分支策略。
- commit 建议：`type(scope): summary`，例如 `docs(architecture): define CDC flow`。

## 6. 变更控制

重命名持久资源、表、列、事件或状态值可能是破坏性变更。必须先评估迁移、回滚、消费者影响和成本；生产命名变化进入 Terraform plan 和人工审批。
