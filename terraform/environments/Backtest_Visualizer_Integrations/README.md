# Backtest storage and GitHub deployment permissions

This root owns only the dedicated private strategy bucket, the backend S3 task
role, and the repository-specific GitHub OIDC deploy role. It does not create a
dev deployment, adopt the existing manually created ECS service, or replace its
network. The inspected `Backtest_Visualizer` state was empty; applying that full
root would risk creating a second stack. These integration resources therefore
have their own S3 state key.

```powershell
terraform init
terraform plan '-out=integrations.tfplan'
terraform apply integrations.tfplan
```

The bucket blocks public access, requires HTTPS, uses SSE-S3, has versioning,
and cannot be destroyed through a routine apply. The production task role can
access only `production/strategies/*`. Local development may use a separate
`development/` prefix with the developer's existing AWS profile. No static AWS
keys or database values are stored here.

Set GitHub's `production` environment to allow **main only**. Its OIDC subject
is `repo:MUNQuantSociety/mqs-backtest-visualizer:environment:production`; both
that environment branch rule and the workflow main-only guard are required.
Set `AWS_DEPLOY_ROLE_ARN`, `ECS_TASK_ROLE_ARN`, `STRATEGY_STORE_S3_BUCKET`, and
`STRATEGY_STORE_S3_PREFIX=production` from these outputs in GitHub settings.

This stack deliberately does not roll ECS. The existing service needs working
database secret references, a secure database connection, the task role, and
the externally maintained authentication/execution-safety requirements before
production is released. See the backend repository's `docs/CI_CD.md`.
