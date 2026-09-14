# V4B 最小成本 CD 证明

V4B 的 CI 与 CD 范围有意不同：GitHub Actions 继续验证完整仓库，AWS CD 仅部署独立的最小 proof stack，不接管或迁移既有 V1–V3 DEV 数据平台。

## 数据流与边界

`GitHub protected main -> CodeConnections -> CodePipeline -> CodeBuild -> TerraformExecution -> cicd-proof`

- 控制面根：`terraform/cicd-control`，状态使用既有 DEV Terraform 状态桶中的独立 `cicd-control/terraform.tfstate` 键。
- DEV proof 根：`terraform/cicd-proof/dev`，复用既有状态桶 `aip-insurance-dev-tfstate-dev01`，独立键为 `cicd-proof/dev/terraform.tfstate`。
- PROD proof 根：`terraform/cicd-proof/prod`，复用同一安全状态桶，但使用独立键 `cicd-proof/prod/terraform.tfstate`；它与 DEV 是独立 Terraform root 和独立状态对象，不使用 workspace。
- 三个状态键均使用既有客户管理 KMS key `alias/insurance/dev/terraform-state`、桶版本控制和 S3 原生 lockfile；不新增状态桶、KMS key 或 DynamoDB。
- DEV/PROD 各只部署一个保留 30 天的 CloudWatch Log Group，并以 Git SHA 与 Pipeline execution ID 标记。没有 RDS、DMS、网络、Glue、ML、RAG 或持续计算副本。

## 发布语义

DEV 合并后自动生成二进制计划，拒绝 delete/replace，应用该计划并通过 AWS CLI 与零漂移计划验证。PROD 生成二进制计划、SHA-256、变更计数和来源元数据；流水线随后停在人工批准。批准后仅应用制品中的同一个二进制计划，并再次检查来源 SHA、制品校验和、AWS 资源和零漂移。

构建权限被拆成三条互不替代的链：DEV deploy、PROD plan、PROD apply。每个 CodeBuild service role 只有日志、制品和 `sts:AssumeRole` 到对应 narrow proof role 的权限。PROD plan role 只能读取 PROD state/KMS 并查看 Log Group，不能创建资源或写 state；只有人工审批后的 PROD apply 项目能假设 PROD apply role。没有 PAT、访问密钥或长期凭证。既有 V3 `Human MFA -> Operator -> TerraformExecution` 链只管理稳定 CD 控制面，不向流水线暴露其完整平台权限，也不让流水线修改自身。

## 成本

CodePipeline 使用 V1 管道；三个 CodeBuild 项目均使用短时 `BUILD_GENERAL1_SMALL`，只在对应阶段运行。S3 制品和 CloudWatch 日志按极小实际用量计费；状态复用既有客户管理 KMS key，因此没有新增 KMS 固定月费，也没有持续计算。一次验证预计为美分级，新增固定月费接近 USD 0（若账号不享有或超出 CodePipeline 免费额度，活跃管道可能按 AWS 当期标准计费）。

## 人工步骤

Terraform 创建的新 CodeConnections 连接最初为 `PENDING`，必须在 AWS Console 完成一次 GitHub App handshake 后才会变为 `AVAILABLE`。真正 PROD 变更必须停在 CodePipeline 的 `PRODApproval`，核对 Git SHA、execution ID、plan SHA-256 和变更计数后再批准。
