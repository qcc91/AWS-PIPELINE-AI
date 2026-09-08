# Phase 1 执行计划 — Terraform Foundation

## 1. 状态与授权边界

- 状态：Human Owner 于 2026-09-08 批准；TASK-INF-001 至 005 可实施，TASK-INF-006 未授权
- 默认 region：`ap-southeast-2`（Sydney）
- 目标环境：DEV；PROD 仅交付独立 environment/state 设计，不创建 PROD 资源
- 当前授权：允许 Worker 委派、Terraform 编码、离线测试与安全的只读 plan；禁止 `terraform apply` 或任何 AWS 资源变更
- 停止规则：任何需要第二区域、新 AWS 服务、扩大安全边界或明显增加持续成本的方案返回 `ARCHITECTURE_DECISION_REQUIRED`

## 2. Phase 1 Scope

Phase 1 仅建立后续数据平台可安全复用的基础设施工程底座：

1. Terraform 版本、provider、目录、模块接口、验证和安全扫描约定。
2. DEV remote state bootstrap：S3 + KMS + S3 native lockfile。
3. PROD 的独立 backend/environment 配置设计，但不创建 PROD backend 或资源。
4. DEV 最小网络基线：VPC、两个私有子网、路由和 S3 Gateway Endpoint；不使用 NAT Gateway。
5. DEV 数据安全基线：KMS、职责分离的 S3 buckets、Block Public Access、TLS-only、versioning/lifecycle。
6. DEV Terraform 执行权限和最小的基础服务角色边界；不预建所有后续服务角色。
7. Glue Data Catalog 分层数据库与 Lake Formation location/基础角色模型。
8. CloudTrail、CloudWatch、SNS 的基础审计/告警路径；订阅端点需 Human Owner 提供后再启用。
9. DEV foundation 的 `fmt/validate/tflint/checkov/test/plan`、成本估算和 Manager review。

### 不在 Phase 1

RDS、DMS、Kinesis、Firehose、Glue jobs/crawlers、Step Functions、EventBridge pipeline、Athena/QuickSight、SageMaker、Bedrock/Knowledge Bases/S3 Vectors、业务数据、生产资源以及任何跨区资源均不创建。

## 3. Terraform Bootstrap Design

### 3.1 目录与状态边界

```text
terraform/
  bootstrap/
    environments/
      dev/                 # Phase 1 可在单独批准后创建
      prod/                # 仅设计，不 apply
  modules/
    kms/
    s3/
    networking/
    iam/
    glue/
    lakeformation/
    monitoring/
  environments/
    dev/                   # DEV foundation root
    prod/                  # PROD root/config only，不 apply
```

DEV 与 PROD 使用不同的 state bucket、KMS key、backend config 和执行角色，不使用 Terraform workspace 作为环境安全边界：

```text
DEV state bucket:  {org}-insurance-dev-tfstate-{account_short}
DEV keys:          bootstrap/terraform.tfstate
                   foundation/terraform.tfstate

PROD state bucket: {org}-insurance-prod-tfstate-{account_short}  # 仅设计
PROD keys:         bootstrap/terraform.tfstate
                   foundation/terraform.tfstate
```

### 3.2 Backend controls

- S3 versioning、Block Public Access、bucket owner enforced、TLS-only bucket policy。
- Customer-managed symmetric KMS key；key policy 只允许获批 bootstrap/admin 与 environment Terraform role。
- backend 设置 `encrypt=true`、`kms_key_id`、`use_lockfile=true`；lock object 为 `<state>.tflock`。
- 不使用 DynamoDB locking：S3 backend 已支持 native lockfile，DynamoDB locking 已被 HashiCorp 标为 deprecated；同时避免引入未批准服务。
- state 与 plan 视为敏感数据：不提交 Git、不写日志、不向 Worker 输出完整内容。
- state bucket 禁止 lifecycle 自动删除 current state；noncurrent version 保留期需在首次 apply 前批准。
- 后端配置使用 partial configuration，不包含凭据；执行使用短期凭据/assume role，不创建长期 access key。

### 3.3 Bootstrap sequence

1. 由获批 AWS principal 在受控本地 state 下执行 DEV bootstrap plan。
2. Manager 审查 plan：预期只创建 DEV state bucket、KMS key/alias 和策略，不允许 destroy/replace。
3. Human Owner 明确授权第一次 bootstrap apply。
4. apply 后验证加密、versioning、public access、TLS policy 和授权拒绝路径。
5. 将 bootstrap state 迁移至 DEV bucket 的 `bootstrap/terraform.tfstate`，验证远程读取和 lock contention。
6. 清理本地 state 前先确认远程版本可恢复；本地临时文件不得进入 Git。

Terraform S3 backend 的 `use_lockfile`、版本控制建议及权限要求依据 [HashiCorp S3 backend 文档](https://developer.hashicorp.com/terraform/language/backend/s3)。

## 4. 预期 AWS Resources

数量是设计上限，最终以 reviewed plan 为准。

| 波次 | DEV 资源 | 预期数量 | 说明 |
|---|---|---:|---|
| Bootstrap | S3 state bucket | 1 | versioned、SSE-KMS、native lockfile |
| Bootstrap | KMS key + alias | 1 | 仅保护 DEV Terraform state |
| Foundation | VPC | 1 | Sydney，RFC1918 CIDR 待实施前冲突检查 |
| Foundation | Private subnets | 2 | 两个 AZ，支持后续 RDS subnet group；Phase 1 不建 RDS |
| Foundation | Route tables | 1–2 | 最小路由，不建 IGW/NAT |
| Foundation | S3 Gateway VPC Endpoint | 1 | 无小时费的 S3 私网路径 |
| Foundation | Platform KMS key + alias | 1 | DEV data/log encryption；后续按职责证明需要才拆 key |
| Foundation | S3 buckets | 最多 6 | Phase 1 为 landing、lakehouse、control、quarantine、documents、audit-logs；artifacts 延至 ML 阶段按需创建 |
| Foundation | IAM roles/policies | 2–4 | Terraform plan/apply 与 CloudTrail logging；不预建业务角色 |
| Foundation | Glue databases | 4 | bronze、silver、gold、control；表尚不创建 |
| Foundation | Lake Formation registrations/grants | 1–4 | lakehouse/control location 与管理员基线；PII grants 后续细化 |
| Foundation | CloudTrail trail | 1 | DEV 账户/区域控制面审计；跨区域捕获配置需 plan 时标明 |
| Foundation | CloudWatch log groups | 1–3 | 明确保留期、KMS 加密 |
| Foundation | Metric filters/alarms | 最多 3 | 高价值安全/交付失败信号，避免高基数 |
| Foundation | SNS topic | 1 | subscription 在告警接收者确认后启用 |

PROD 预期创建数量在 Phase 1 为 **0**。PROD 目录、变量和 backend 契约必须可验证，但 backend bucket 本身也不创建。

## 5. 计划委派任务

以下是批准后才发送给 Worker 的任务契约；当前尚未委派。

### TASK-INF-001 — Terraform 工程骨架与离线质量门禁

**OWNER**：Worker 1 — Infrastructure / DevOps / QA

**OBJECTIVE**：建立 Terraform 目录、版本约束、provider 约束、共享 tags/validation 约定，以及不访问 AWS 的格式、validate、lint 和安全扫描入口。

**CONTEXT**：Gate 1 已批准；默认 Sydney；DEV-first；不得 apply。

**INPUTS**：AGENTS.md、naming/development/cost standards、本执行计划。

**OUTPUTS**：空资源 root/module skeleton、tool version 文件、validation/buildspec、基础测试说明。

**FILES ALLOWED TO MODIFY**：`terraform/**`、`tests/infrastructure/**`、`buildspecs/terraform-validate.yml`、相关 Terraform 开发文档。

**FILES NOT ALLOWED TO MODIFY**：`src/**`、`sample-data/**`、数据契约/ADR、任何 AWS 外部状态。

**DEPENDENCIES**：Human 批准本计划。

**ACCEPTANCE CRITERIA**：显式 `ap-southeast-2`；DEV/PROD root 分离；无资源 apply；无凭据；`fmt -check`/`validate` 通过；tflint/checkov 配置可执行。

**TESTS REQUIRED**：offline fmt/validate、静态扫描、secret scan、目录边界检查。

**RETURN FORMAT**：files changed、summary、commands/results、risks、assumptions、明确声明未创建 AWS 资源。

### TASK-INF-002 — DEV Remote State Bootstrap

**OWNER**：Worker 1

**OBJECTIVE**：实现 DEV state bucket/KMS/native lockfile bootstrap，并为 PROD 提供独立但不执行的同构配置。

**INPUTS**：TASK-INF-001、bootstrap design、AWS account ID/获批执行 principal。

**OUTPUTS**：bootstrap module/root、backend partial config templates、迁移/恢复/验证 runbook、资源成本估算。

**FILES ALLOWED TO MODIFY**：`terraform/bootstrap/**`、bootstrap 相关 module/tests/docs。

**FILES NOT ALLOWED TO MODIFY**：业务 modules、`src/**`、Phase 0 data contracts；不得执行 apply。

**DEPENDENCIES**：TASK-INF-001。

**ACCEPTANCE CRITERIA**：DEV/PROD 不同 bucket/key/KMS/role；versioning/public block/TLS/KMS；`use_lockfile=true`；无 DynamoDB；plan 无意外资源；PROD plan/config 不 apply。

**TESTS REQUIRED**：fmt/validate/tflint/checkov、policy tests、plan review checklist；实际 lock/recovery test 延后到 apply 获批后。

**RETURN FORMAT**：标准 Worker 返回格式，附资源 create/change/destroy 摘要与估算。

### TASK-INF-003 — DEV 网络与安全存储 Modules

**OWNER**：Worker 1

**OBJECTIVE**：实现可复用 networking、KMS、S3 modules，不部署。

**INPUTS**：批准架构、Sydney region、24h RPO/4h analytical RTO 项目假设。

**OUTPUTS**：无 NAT 的 VPC/两私网/S3 endpoint module；DEV bucket/KMS controls；PROD 可配置接口。

**FILES ALLOWED TO MODIFY**：`terraform/modules/networking/**`、`kms/**`、`s3/**`、对应 tests/docs。

**FILES NOT ALLOWED TO MODIFY**：bootstrap、业务 ingestion/AI 目录；不得 apply。

**DEPENDENCIES**：TASK-INF-001；可与 TASK-INF-002 编码并行，但集成依赖 bootstrap 契约。

**ACCEPTANCE CRITERIA**：CIDR validation；两个 AZ；无 NAT/IGW；S3 endpoint；bucket public block/TLS/KMS/versioning/lifecycle；危险删除保护；tags 完整。

**TESTS REQUIRED**：fmt/validate/tflint/checkov、Terraform tests/policy assertions、成本检查。

**RETURN FORMAT**：标准 Worker 返回格式，列出安全例外和持续成本。

### TASK-INF-004 — IAM、Catalog/Lake Formation 与 Observability Modules

**OWNER**：Worker 1

**OBJECTIVE**：实现最小 IAM 执行边界、Glue databases、Lake Formation location/admin baseline、CloudTrail/CloudWatch/SNS module，不部署。

**INPUTS**：四类 PII role baseline、审计/日志要求、TASK-INF-003 outputs。

**OUTPUTS**：IAM/glue/lakeformation/monitoring modules 与权限负面测试设计。

**FILES ALLOWED TO MODIFY**：`terraform/modules/iam/**`、`glue/**`、`lakeformation/**`、`monitoring/**`、对应 tests/docs。

**FILES NOT ALLOWED TO MODIFY**：业务 Glue jobs、RDS/DMS/Kinesis/AI；不得创建未批准服务或 apply。

**DEPENDENCIES**：TASK-INF-001；接口集成依赖 TASK-INF-003。

**ACCEPTANCE CRITERIA**：无无理由 `*`；日志无 PII；明确 retention；Gold/PII role boundary 可扩展；RAGApplication 无客户数据湖权限；SNS 无未知订阅。

**TESTS REQUIRED**：IAM/LF allow-deny assertions、fmt/validate/tflint/checkov、CloudTrail bucket policy/KMS policy tests。

**RETURN FORMAT**：标准 Worker 返回格式，附权限矩阵和未决 identity mapping。

### TASK-INF-005 — DEV/PROD Environment Integration 与 Plan

**OWNER**：Worker 1

**OBJECTIVE**：把已审查 modules 接入 DEV root；建立 PROD 独立配置但禁止 apply；生成 DEV reviewed plan 和正式成本估算。

**INPUTS**：TASK-INF-002/003/004、AWS account/identity、保留期、告警接收者、预算阈值。

**OUTPUTS**：DEV foundation root、PROD non-deployed root、plan summary、cost model、rollback/cleanup plan。

**FILES ALLOWED TO MODIFY**：`terraform/environments/dev/**`、`terraform/environments/prod/**`、相关 tests/docs/buildspec。

**FILES NOT ALLOWED TO MODIFY**：数据/ML/RAG implementation；不得 apply DEV 或 PROD。

**DEPENDENCIES**：TASK-INF-002、003、004；DEV backend apply/migration 是否先执行由 checkpoint 决定。

**ACCEPTANCE CRITERIA**：provider 固定 Sydney；环境 state/roles/keys 独立；DEV plan 只有预期资源；PROD 仅 validate；0 destroy；成本和安全差异清楚。

**TESTS REQUIRED**：全部 IaC 门禁、plan JSON assertions、资源计数/region/公共访问/NAT/PII policy checks。

**RETURN FORMAT**：标准 Worker 返回格式，附 plan create/change/destroy、月成本区间、known risks。

### TASK-INF-006 — 经批准后的 DEV Apply 与验证（暂不授权）

**OWNER**：Worker 1

**OBJECTIVE**：在 Human 明确批准 reviewed plan 后，依序 apply bootstrap 与 DEV foundation，并执行恢复、锁、权限、审计和清理验证。

**DEPENDENCIES**：TASK-INF-005、Manager code/security/cost review、Human 明确授权 AWS 资源创建。

**FILES ALLOWED TO MODIFY**：仅测试证据、runbook 和必要的小修复；任何 plan 变化重新评审。

**FILES NOT ALLOWED TO MODIFY**：PROD；不得创建 plan 外资源。

**ACCEPTANCE CRITERIA**：实际资源与 plan 一致；remote lock/version recovery、public deny、KMS、CloudTrail delivery、LF/IAM deny tests 通过；成本标签完整。

**TESTS REQUIRED**：post-apply smoke/security/integration、drift check、`terraform plan -detailed-exitcode` 期望无漂移。

**RETURN FORMAT**：资源清单、apply 结果、测试证据、费用观察、回滚状态、known issues。此任务完成后由 Manager 准备 Gate 2。

## 6. Task Dependencies

```text
Current Human review
        │
        v
TASK-INF-001 (engineering skeleton)
   ├──────────────> TASK-INF-002 (state bootstrap code)
   ├──────────────> TASK-INF-003 (network/storage modules)
   └──────────────> TASK-INF-004 (IAM/catalog/monitoring modules)
                          │
             002 + 003 + 004 + Manager reviews
                          v
              TASK-INF-005 (environment integration/plan)
                          v
          Human approval of exact AWS plan and cost
                          v
              TASK-INF-006 (DEV apply/verification)
                          v
                 Manager Gate 2 review
```

Manager 在每个 Worker 返回后执行架构、安全、成本、测试和文件范围审查；缺陷优先返回原 Worker 修复。TASK-INF-003/004 可在接口冻结后并行，但共享 module/output 变更由 Manager 集成。

## 7. Estimated Cost Impact

以下为 `ap-southeast-2`、极低数据量、USD、税前的计划级区间，不是报价；正式数字以实施当日 AWS Pricing Calculator 和 reviewed plan 为准。

| 范围 | 主要成本 | 初始估算 |
|---|---|---:|
| DEV bootstrap only | 1 个 KMS key、极小 S3 state/version/request | 约 USD 1–2/月 |
| DEV foundation steady | 1 个平台 KMS key、少量 S3/log storage、CloudWatch alarms/logs、SNS requests | 约 USD 3–10/月 |
| Phase 1 合计 steady | bootstrap + foundation | 约 USD 4–12/月 |
| PROD | 不创建 | USD 0/月 |

估算假设：无 NAT Gateway、无 interface endpoints、无 RDS/DMS/Kinesis/Glue compute、无大量 CloudTrail data events、日志量低于约 1 GB/月、S3 数据为 MB 到低 GB 级。若加入 interface endpoint、额外 CloudTrail event copy/data events、高日志量或更多 KMS keys，必须重算并在 plan 中突出。

RDS/DMS 将在后续 ingestion phase 成为主要持续成本，不计入 Phase 1。AWS 对 RDS/DMS 均按运行容量/时间计费，正式选择前必须比较 DEV 启停与 DMS provisioned/serverless。

## 8. Checkpoints 与停止条件

### P1-CP0 — Human Plan Review（已通过）

Human Owner 已于 2026-09-08 批准：Phase 1 scope/non-scope、bootstrap/state isolation、预期资源上限、任务契约、USD 4–12/月计划成本边界。Manager 可委派 TASK-INF-001 至 005；仍不授权 AWS apply。

### P1-CP1 — First AWS Change Approval

在任何资源创建前，Manager 提交：bootstrap/foundation 精确 Terraform plan、create/change/destroy、IAM/KMS/LF 安全摘要、正式成本、执行 identity、state recovery 与 rollback。Human 必须明确批准后才允许 TASK-INF-006。计划变化需重新审批。

### Gate 2 — Core Infrastructure Ready

仅在获批 DEV apply、测试和 Manager review 完成后提交 Gate 2；报告实际资源、IAM/security、成本、plan/drift 和 known issues。Gate 2 不授权下一阶段 PROD 或业务实现。

### 立即停止条件

- Sydney 不支持必需能力或模型；
- 要求第二区域、NAT Gateway、未批准 AWS 服务或 PROD 资源；
- plan 包含意外 destroy/replace、公共访问、宽泛 IAM 或超过成本边界；
- AWS account、执行 principal、CIDR 冲突、state 保留期等阻止安全 plan/apply 的输入缺失。

上述情况返回 `ARCHITECTURE_DECISION_REQUIRED` 或向 Human 请求明确决定，不作静默假设。

## 9. 当前未决输入

在 TASK-INF-002 plan 或任何 apply 前需要：AWS account ID/组织短标识、获批短期执行 principal/role、VPC CIDR 冲突信息、Terraform state noncurrent version 保留期。在 observability apply 前还需要告警接收者；在完整 cost gate 前需要月预算阈值和币种确认。

当前执行 TASK-INF-001 至 005，下一 Human 停止点为 P1-CP1；TASK-INF-006 未授权。
