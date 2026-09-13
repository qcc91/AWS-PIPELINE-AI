# V3 数据治理与 PII 访问设计

> 2026-09-13 完成说明：下文的 2026-09-12 “当前基线/待实施”内容保留为
> 变更前证据。V3 已部署两个注册位置、独立 persona grants 与 hybrid opt-in；
> Analyst Gold ALLOW/Silver DENY、MLEngineer 批准 Gold ALLOW/Silver DENY、
> Secrets DENY 和 RAG 零结构化授权均通过真实测试。最终证据见
> `docs/v3-completion-review.md`。

## 范围与证据状态

本设计基于当前 `sql/cdc/001_schema.sql`、三个 Glue 作业、V1/V2 真实运行报告
和现有 Lake Formation Terraform 模块。它只覆盖已经实现的 Glue/Iceberg 表，
不把数据契约中的后续设计实体描述为已部署。

2026-09-12 已使用恢复后的 AWS CLI 会话完成只读复核：账户
`199476069493`、区域 `ap-southeast-2`，调用身份仍为 root（仅用于本次读取）。
Glue Catalog 实际存在 `insurance_dev_bronze`,`insurance_dev_silver`,
`insurance_dev_gold`,`insurance_dev_control`；Bronze 13 表、Silver 13 表、Gold
16 表，表名和列与本文件分类一致。

Lake Formation 当前真实基线为：

- Data Lake Admin 只有既有
  `role/service-role/AmazonSageMakerAdminIAMExecutionRole`；不是计划中的独立 LF
  admin。
- `CreateDatabaseDefaultPermissions` 和 `CreateTableDefaultPermissions` 都向
  `IAM_ALLOWED_PRINCIPALS` 授予 `ALL`。
- `list-resources` 返回空集合，没有 Lakehouse/control S3 location 注册。
- `list-permissions` 首个返回页仅观察到 Silver database：root 拥有含 grant option 的
  `ALL,ALTER,CREATE_TABLE,DESCRIBE,DROP`，`IAM_ALLOWED_PRINCIPALS` 拥有 `ALL`。
- 首页没有 DataEngineer、Analyst、MLEngineer 或 RAGApplication grant；响应带有
  `NextToken`，紧接着的只读分页复核因 CLI 再次失去登录凭证而未完成，故不能把
  “全账户零 persona grant”作为已证实结论。

因此现状是 Glue Catalog 已有真实表，但 LF 尚未形成数据访问边界；仓库 DEV
配置中的 deferred outputs 与 AWS 基线一致。以上是整改输入，不是治理通过证明。

## 当前实际表与字段分类

公共技术列（如存在）`_run_id,_source_system,_source_object,_source_file_id,
_ingested_at,_effective_at,_schema_version,_record_hash,_source_change_id,
_operation,_source_order` 均为 `PII NO / LOW`；但技术列不得携带原始记录或秘密。

| 数据域/实际列 | PII | 等级 | 允许角色 |
|---|---|---|---|
| Customer `first_name,last_name,date_of_birth,email,phone` | YES | HIGH | DataEngineer |
| Claim `description`；quarantine `source_record/original_record` | YES | HIGH | 获批 DataEngineer 调查职责 |
| `customer_id,policy_number,claim_number,provider_reference` | YES | MEDIUM | DataEngineer；其他角色仅经明确列授权 |
| 可回连上述键的 `policy_id,claim_id,payment_id` | YES | MEDIUM | DataEngineer；批准的 Gold 用途可给 Analyst/MLEngineer |
| 单笔 `premium_amount,claim_amount,approved_amount,payment_amount`、结果/标签/概率 | NO | MEDIUM | DataEngineer；按用途给 Analyst/MLEngineer |
| 产品、broker/branch、粗粒度 region、vehicle、coverage 属性 | NO | LOW | DataEngineer、Analyst；特征表中可给 MLEngineer |
| Gold 汇总及审计计数/时间/状态 | NO | LOW | 按矩阵授权 |

Bronze `claim` 与 Silver `claim` 即使当前 DEV 文件是合成数据，仍按可接收生产
broker 文件的契约分类。`broker_name` 是虚构企业展示名，不是个人姓名。

## 最小 Lake Formation 执行矩阵

| 角色 | 数据库 | 资源 | 权限 |
|---|---|---|---|
| DataEngineer | bronze/silver/gold/control | 当前表及未来通过受控流程创建的表 | database `DESCRIBE,CREATE_TABLE,ALTER`; table `DESCRIBE,SELECT,INSERT,DELETE,ALTER`; 已注册位置 `DATA_LOCATION_ACCESS` |
| Analyst | gold | `claim_daily_summary`,`claim_daily_summary_cdc`,`broker_performance` 和七个 `dim_*` 参考表 | database `DESCRIBE`; table `SELECT,DESCRIBE` |
| Analyst | gold | `fact_claim`,`fact_claim_cdc`,`fact_claim_enriched`,`policy_performance` | `TableWithColumns SELECT`，排除 `customer_id,claim_number,policy_number,provider_reference,description`；只包含业务分析所需列 |
| Analyst | gold | `claim_risk` | `TableWithColumns SELECT`：`claim_id,high_risk_probability,risk_level,model_version,prediction_timestamp` 及必要 lineage 列 |
| MLEngineer | gold | `claim_risk_features`,`claim_risk` | database `DESCRIBE`; table `SELECT,DESCRIBE`；不得扩展至通用 Silver |
| RAGApplication | 无 | 无结构化 Lakehouse 资源 | 零 LF grant |

`claim_risk_features` 的 `claim_id` 是模型输出回连所需的最小间接标识；该例外不
授权 customer/policy/claim number、姓名、联系方式或自由文本。Analyst 的事实
表 inclusion list 必须在应用前从 Glue Catalog 实际列生成并代码评审，不使用
“排除当前已知列”的开放式授权来容忍未来 schema drift。

Lake Formation Admin、Terraform execution、DataEngineer、Analyst、MLEngineer、
RAGApplication 和数据位置访问角色必须是不同的非 root IAM role。LF grant 还需
配套最小 Athena、Glue Catalog、S3、KMS 权限；这些 IAM 权限不得独立授予绕过
LF 的数据路径。删除 `IAMAllowedPrincipals` 默认授权前，先确认所有 Glue 作业
角色和消费者角色具有显式 LF 权限，避免中断 V2 流水线。

## 只读基线命令

实施前后均在 `ap-southeast-2` 运行并保存脱敏结果：

```powershell
aws sts get-caller-identity
aws glue get-databases --region ap-southeast-2
aws glue get-tables --region ap-southeast-2 --database-name insurance_dev_bronze
aws glue get-tables --region ap-southeast-2 --database-name insurance_dev_silver
aws glue get-tables --region ap-southeast-2 --database-name insurance_dev_gold
aws lakeformation get-data-lake-settings --region ap-southeast-2
aws lakeformation list-resources --region ap-southeast-2
aws lakeformation list-permissions --region ap-southeast-2
```

2026-09-12 的实际输出确认了 13/13/16 张 Bronze/Silver/Gold 表、默认
`IAMAllowedPrincipals=ALL`、零 registered location、一个既有 SageMaker admin，
以及权限结果首页中 Silver 上的 root 与 `IAMAllowedPrincipals` 权限。完整权限
分页仍须补录；实施后的
预期差异是：精确 location 已注册、独立 admin/persona grants 与矩阵一致、默认
兼容授权和 root grant 已安全移除。删除前仍须先验证 Glue 作业显式权限，不能
把本节当作直接撤销授权的操作指令。

## 正反 Athena/LF 验证

实施后必须分别取得各命名角色的临时凭证运行 Athena，不能使用 root 模拟：

```sql
-- Analyst 正向
SELECT * FROM insurance_dev_gold.claim_daily_summary LIMIT 5;
SELECT claim_id, high_risk_probability, risk_level
FROM insurance_dev_gold.claim_risk LIMIT 5;

-- Analyst 反向（应 AccessDenied）
SELECT * FROM insurance_dev_silver.customers LIMIT 1;
SELECT customer_id, claim_number
FROM insurance_dev_gold.fact_claim_enriched LIMIT 1;

-- MLEngineer 正向
SELECT claim_id, submitted_at, claim_amount, high_risk_claim
FROM insurance_dev_gold.claim_risk_features LIMIT 5;

-- MLEngineer 反向（应 AccessDenied）
SELECT first_name, email FROM insurance_dev_silver.customers LIMIT 1;
SELECT description FROM insurance_dev_silver.claims LIMIT 1;

-- RAGApplication 反向（应 AccessDenied）
SELECT * FROM insurance_dev_gold.claim_daily_summary LIMIT 1;
```

每个正向查询预期 `SUCCEEDED`；每个反向查询预期因 LF 授权不足失败。另以
`lakeformation list-permissions --principal ...` 验证 grant 清单与矩阵精确相等，
并确认 Analyst/MLEngineer 无 Bronze、quarantine、直接 PII 列或任意表 wildcard。
验证记录必须保存 query execution ID、assumed-role ARN、时间、SQL 摘要和结果，
不得保存查询到的 PII 值。

### V3 apply 前测试设计复核（2026-09-12）

当前 Terraform 使用 Lake Formation hybrid access：保留 V2 pipeline 的 IAM
兼容路径，只把 Analyst 和 MLEngineer 对批准 Gold 表显式 opt-in 到 LF。这个
混合迁移可接受，但实测必须同时证明：

- 两个精确 S3 location 已注册，角色是独立 registration role；
- LF admin 已从既有 SageMaker role 切换为 TerraformExecution；
- `IAM_ALLOWED_PRINCIPALS` 默认值若为兼容 V2 而保留，只能由未 opt-in 的既有
  pipeline 使用，不能让已 opt-in persona 绕过显式 grants；
- Analyst/MLEngineer 只在批准表上存在 opt-in，RAGApplication 没有 LF grant；
- 旧 root Silver grant 的处理结果被明确记录，不可误报成 persona 隔离已完成。

发现一个 apply 前不一致：当前 `analyst_gold_tables` 把
`policy_performance` 整表授权给 Analyst，而实际 Catalog 表含 MEDIUM/PII YES 的
`policy_id`。在实现 `TableWithColumns` inclusion-list 之前，最小安全修复是从
Analyst 整表清单移除 `policy_performance`。该问题解决前，不能把 Analyst PII
隔离测试标记为通过。

身份链必须从 Human 所称的 `aip-dev-human` 短期登录会话开始，依次 assume
`insurance-dev-operator-role`，再分别 assume persona role。每次都先执行
`sts get-caller-identity`，确认 ARN 是本次预期角色；不得从 root 直接测试，也不
得把返回的 access key、secret 或 session token 写入文件或命令输出。可在单个
PowerShell 进程内仅用内存变量切换临时环境变量：

```powershell
$operator = aws sts assume-role --role-arn arn:aws:iam::199476069493:role/insurance-dev-operator-role --role-session-name v3-operator-test --query Credentials --output json | ConvertFrom-Json
$env:AWS_ACCESS_KEY_ID = $operator.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $operator.SecretAccessKey
$env:AWS_SESSION_TOKEN = $operator.SessionToken
$persona = aws sts assume-role --role-arn arn:aws:iam::199476069493:role/insurance-dev-analyst-role --role-session-name v3-analyst-test --query Credentials --output json | ConvertFrom-Json
```

为 DataEngineer、Analyst、MLEngineer 分别新建 `$persona` 会话并立即运行测试；
不要复用上一 persona 的环境变量。验证项及预期：

| 会话 | 操作 | 预期 |
|---|---|---|
| DataEngineer | Glue 获取 Bronze/Silver/Gold 表；Athena 查询 Gold | ALLOW |
| Analyst | Athena 查询 `claim_daily_summary`、批准 `dim_*`/`broker_performance` | ALLOW |
| Analyst | Athena 查询 Bronze/Silver、未批准事实表或直接/间接 PII 列 | DENY |
| Analyst | `secretsmanager:GetSecretValue` 任意 secret | 显式 DENY |
| MLEngineer | Athena 查询 `claim_risk_features`,`claim_risk` | ALLOW |
| MLEngineer | Athena 查询 Silver `customers` 或 `claim.description` | DENY |
| MLEngineer | `secretsmanager:GetSecretValue` 任意 secret | 显式 DENY |

本 Worker 进程在身份 bootstrap 后没有可用 AWS profile 或 `AWS_*` 凭证；按包
要求等待后只重试了一次 `sts get-caller-identity`，结果仍为 `NoCredentials`。
因此本节是可执行测试清单，不是 runtime 通过证据。Foundation apply 和 persona
实测须由持有 Human 临时登录上下文的 Manager 进程执行。

## 实施顺序建议

1. 只读盘点实际 Catalog/LF/IAMAllowedPrincipals 状态。
2. 创建并验证互相独立的角色及数据位置访问角色。
3. 注册 lakehouse/control 精确 S3 位置，先给 Glue 作业和 DataEngineer 显式权限。
4. 以 inclusion-list 建立 Analyst/MLEngineer grants；RAGApplication 保持零 grant。
5. 逐角色完成正反 Athena 测试，再移除会绕过 LF 的默认授权。
6. 重跑 Batch、CDC、DQ、ML 既有回归，确认治理没有破坏 V2 行为。

本文件是实施输入而非部署证明；AWS 资源只有在 Terraform apply 和真实角色验证
完成后才能标记为已治理。
