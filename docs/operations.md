# Operations runbook

All commands assume `terraform/environments/Livetrading` as the working directory and a
configured AWS profile in `us-east-2`.

## Credential handling — read before your first command

**This repository is public** (`MUNQuantSociety/MQS_AWS_INFRA`). A credential
pushed here is compromised the second it lands: GitHub keeps unreachable objects
after a force-push, forks keep their own copy, and the public events firehose is
scraped continuously. Deleting the commit does not undo it. The only remedy is
rotation.

### One-time setup per clone

Git does not transport hooks, so this is not automatic:

```bash
git config core.hooksPath .githooks
```

That activates [`.githooks/pre-commit`](../.githooks/pre-commit), which refuses
to commit credential-shaped paths (`*.tfvars`, `*.tfstate`, `.env*`, `*.pem`,
`*accessKeys*.csv`) and credential-shaped values in staged content. It is a
convenience layer only — `--no-verify` skips it. The authority is
[`.github/workflows/secret-scan.yml`](../.github/workflows/secret-scan.yml),
which runs gitleaks over the **full history** on every push and cannot be
skipped from a developer machine.

Verify the guard is live before trusting it:

```bash
git check-ignore -v terraform/environments/Livetrading/terraform.tfvars
```

An empty result means the ignore rule is NOT matching — stop and fix
`.gitignore` before writing any real value to disk.

### Prefer environment variables over `terraform.tfvars`

Terraform reads a sensitive variable from `TF_VAR_<name>` exactly as it would
from a tfvars file. Using the env-var route means **no plaintext credential file
exists on disk at all**, which removes the whole class of accidents: a
force-add, a `cp -r` into a new environment directory, an editor backup file, or
OneDrive syncing the tree to another machine. This tree does live under
OneDrive, so that last one is not hypothetical.

```bash
cp .env.example .env      # gitignored by the `.env*` rule
chmod 600 .env            # git-bash honours this; on plain Windows use file ACLs
set -a && . ./.env && set +a
terraform plan
```

If you do use `terraform.tfvars`, keep it mode 600, never copy it between
environment directories, and never pass `-var` on the command line — arguments
land in shell history and in the process list.

### Commands that leak, and what to run instead

| Do not run | Why | Instead |
|---|---|---|
| `terraform plan -out=tfplan` | The plan file embeds every root variable value in cleartext, including passwords | Plan without `-out`; if you need one, treat it as a secret and delete it |
| `terraform show -json` / `terraform state pull` piped into a file | Non-write-only attributes appear in cleartext | Read specific outputs with `terraform output -raw <name>` |
| `terraform output` with no argument, in CI | Prints every output, sensitive ones included | `terraform output -raw <name>`, one at a time |
| `aws ssm put-parameter --value '<secret>'` | Lands in shell history and `ps` output | `--value "file:///path"`, then delete the file |
| `aws ssm get-parameter --with-decryption` in a shared terminal | Prints the credential to a scrollback that may be screenshotted | Only when you actually need the value; clear scrollback after |
| `terraform apply` with `TF_LOG=DEBUG` | Debug logs contain request bodies with credential values | Leave `TF_LOG` unset, or write to a gitignored path and delete it |

The write-only arguments (`value_wo`, `password_wo`) already keep SSM parameter
values and the RDS master password out of Terraform state and plan output — see
[modules/Livetrading/ssm-parameters](../terraform/modules/Livetrading/ssm-parameters/main.tf).
That protection covers those specific attributes, not the tfvars file you typed
them into.

### Placeholders now fail the plan

`db_secret_values`, `api_secret_values` and `market_data_secret_values` all carry
`REPLACE_ME` defaults so the modules parse without credentials. Each now has a
`validation` block rejecting that value, so a forgotten tfvars fails at plan
time instead of provisioning RDS with the literal master password
`REPLACE_ME`. `MARKET_DATA_SSLMODE` is likewise constrained to
`require`/`verify-ca`/`verify-full`, because that connection crosses the public
internet and `prefer` silently downgrades to plaintext.

### If a credential does reach GitHub

Order matters — rotate first, clean history second, because the credential is
already scraped by the time you notice.

1. Rotate the credential at the source (IAM, RDS, the vendor console).
2. `aws ssm put-parameter --overwrite` the new value, then
   `aws ecs update-service --force-new-deployment` so running tasks pick it up.
3. Only then rewrite history (`git filter-repo`), and open a GitHub support
   request to expire the cached objects — a force-push alone leaves them
   reachable by SHA.
4. Check CloudTrail for use of the exposed credential between push and rotation.

> **Nothing is deployed yet — the next apply builds the whole stack.**
> Verified against the HCP API and AWS on 2026-08-03.
>
> `MQS_AWS_INFRA_LIVE` (org `MQS`) exists and is bound correctly, but it holds
> **no state**: zero resources, zero state versions, and no run has ever
> executed. `MQS_AWS_INFRA_BTV` is likewise empty. In `us-east-2` the account has
> no VPC beyond the default, no RDS instance, no `mqsmaster-prod-cluster`, no
> `/mqsmaster-prod/*` SSM parameters and no IAM OIDC provider.
>
> An earlier local state exists in this stack's directory as `terraform.tfstate`
> (gitignored, `serial=56`) and tracks **zero** resources — the stack was managed
> locally, then emptied. It was never migrated to HCP, and there is nothing in it
> to migrate. `terraform init` may offer to copy it up. Accepting is safe **only
> when the source is a state you have approved and the destination is empty** —
> re-check both before agreeing, because these facts age.
>
> Inspect the two sides separately. Do not use `terraform state list` for this:
> it reports whichever state is currently configured — the local file before
> `init`, the remote workspace after — so it silently answers a different question
> depending on when you run it.
>
> ```bash
> # Source: read the local file directly, independent of any backend config.
> jq -r '"serial=\(.serial) resources=\((.resources // []) | length)"' terraform.tfstate
>
> # Destination: confirm the workspace you are bound to, then its resource count.
> grep -A6 'cloud {' terraform.tf        # organization + workspace name
> ```
>
> Read the destination count from the workspace's page in HCP, or via the API —
> `GET /api/v2/organizations/<org>/workspaces/<name>`, field
> `attributes.resource-count`.
>
> Proceed only when the destination is empty. If **either** side tracks
> resources, **stop**: copying a populated local state into a workspace that
> already holds one silently picks a winner, and the losing resources keep
> running while nothing manages them. Reconcile deliberately with
> `terraform state pull` / `push` or targeted imports instead of accepting the
> prompt.
>
> So `terraform apply` is a **full create**, not an incremental change. Budget for
> it: a VPC with one NAT gateway (~$32/mo at `single_nat_gateway = true`), an RDS
> `db.t4g.small` with 100 GB gp3, the ECS cluster, both services, the SSM parameter groups and
> the scheduler. Read the plan before confirming.
>
> **What this means for the warnings below.** Because there is no state, the usual
> hazards are inert: a plan cannot propose destroying resources it does not track,
> and `module.github_oidc` will **create** `aws_iam_openid_connect_provider.github`
> rather than collide with an existing one. `terraform import` is not needed. It
> becomes necessary only if the account-global provider
> (`token.actions.githubusercontent.com`) is created out of band first — then the
> apply fails partway with `EntityAlreadyExists`. Confirm before applying:
>
> ```bash
> aws iam list-open-id-connect-providers || echo "LOOKUP FAILED - do not proceed"
> ```
>
> Expect an empty list. Treat a **failed** call as unknown, not as empty: an
> `AccessDenied` prints nothing to stdout, which reads identically to "no
> providers" and would send you into an apply that then dies on
> `EntityAlreadyExists`.
>
> A non-empty list does **not** by itself mean the GitHub provider exists — the
> account may hold providers for other identity providers entirely. Check each
> ARN's `Url` and act only on an exact match for
> `token.actions.githubusercontent.com`:
>
> ```bash
> set -eu
> arns=$(aws iam list-open-id-connect-providers \
>          --query 'OpenIDConnectProviderList[].Arn' --output text)   # aborts on failure
> for arn in $arns; do
>   url=$(aws iam get-open-id-connect-provider \
>           --open-id-connect-provider-arn "$arn" --query Url --output text)
>   printf '%s -> %s\n' "$arn" "$url"
> done
> ```
>
> `set -eu` is the point: without it a failed lookup prints an empty `url` and the
> loop carries on, so an error is indistinguishable from a provider whose URL does
> not match.
>
> Import only the ARN whose `Url` is exactly
> `token.actions.githubusercontent.com`. Providers for any other URL are
> unrelated — leave them unmanaged and let Terraform create the GitHub one.
>
> ```bash
> terraform import module.github_oidc.aws_iam_openid_connect_provider.github \
>   arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
> ```
>
> **Working directory.** Already correct on both workspaces
> (`/terraform/environments/Livetrading` and
> `/terraform/environments/Backtest_Visualizer`). Terraform cannot change a
> workspace setting, so if either is ever renamed again, fix the setting by hand
> before the next run. Both workspaces run in **local** execution mode: runs
> happen on your machine with your AWS credentials and HCP only stores state, so
> a stale working-directory path surfaces as a local error rather than a remote
> run planning against an empty directory.
>
> Two stacks must never share one workspace — one workspace holds one state, so
> each stack's plan would propose destroying the other's resources.

## Deploy

```bash
cd terraform/environments/Livetrading
cp terraform.tfvars.example terraform.tfvars   # fill real secret values
terraform init -upgrade                        # -upgrade required: AWS provider is now ~> 6.28
terraform plan
terraform apply
```

> The AWS provider constraint moved from `~> 5.60` to `~> 6.28` when the VPC
> module was adopted. A workspace initialised before that has a lockfile pinned
> to 5.x and `plan` will refuse until `terraform init -upgrade` is run once.

Outputs after apply:

```
ecr_repository_url            = "<acct>.dkr.ecr.us-east-2.amazonaws.com/livetradingbot"
ecs_cluster_name              = "mqsmaster-prod-cluster"
market_task_definition_family = "mqsmaster-prod"
log_group_name                = "/ecs/mqsmaster-prod"
rds_endpoint                  = "<id>.<region>.rds.amazonaws.com:5432"
```

## First image push

Terraform adopts the existing `livetradingbot` repo rather than creating it, so
images already present stay put. Tasks still fail with `CannotPullContainerError`
if `image_tag` names a tag that is not in the repo — the tag is resolved by ECS at
task start, not by Terraform, so a bad value applies cleanly and only breaks at
runtime.

Either merge to `main` and let CI push, or push manually:

```bash
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin <acct>.dkr.ecr.us-east-2.amazonaws.com
```

```bash
cd ../MQSMaster && docker build -t livetradingbot:1.0.5-5 . && docker tag livetradingbot:1.0.5-5 <acct>.dkr.ecr.us-east-2.amazonaws.com/livetradingbot:1.0.5-5 && docker push <acct>.dkr.ecr.us-east-2.amazonaws.com/livetradingbot:1.0.5-5
```

Then set `image_tag` in `terraform.tfvars` to the tag you just pushed
(`1.0.5-5` above) and re-apply. It is currently pinned to `1.0.5-4`; pushing a
new tag without bumping this deploys the old image.

Note this only governs the *first* revision of the task definition — the market
family carries `ignore_changes = [container_definitions]`, so after that CI
re-registration is what moves the image. There is no ECS Service to update: the
schedule targets the task definition family, so the next scheduled run picks up
the newest ACTIVE revision on its own.

## Manually trigger the market task

```bash
aws ecs run-task --cluster $(terraform output -raw ecs_cluster_name) --task-definition $(terraform output -raw market_task_definition_family) --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json task_subnet_ids | jq -r 'join(",")')],securityGroups=[$(terraform output -raw task_security_group_id)],assignPublicIp=DISABLED}"
```

`assignPublicIp` **must be `DISABLED`**. `task_subnet_ids` now returns private
subnets, and Fargate rejects a task that asks for a public IP in a subnet with no
route to an internet gateway. Egress still works — it goes out via the NAT
gateway.

## Logs

```bash
aws logs tail /ecs/mqsmaster-prod --since 1h --follow
```

Only the market task writes here, under the `mqsmaster/*` stream prefix. Between
sessions the group is silent — that is expected, not a failure. To confirm a
session actually ran, list the streams rather than tailing:

```bash
aws logs describe-log-streams --log-group-name /ecs/mqsmaster-prod --order-by LastEventTime --descending --max-items 5
```

## Rotating secrets

Initial values come from `terraform.tfvars`. Values are passed as **write-only**
arguments (`value_wo`), so they are sent to AWS but never written to state or
plan files, and Terraform cannot diff them. An update fires only when the paired
`value_wo_version` changes — which means console or CLI rotations are **not**
overwritten by a later `terraform apply`.

**Preferred: rotate directly in AWS.** Each credential is a separate SecureString
parameter, so rotate them one at a time rather than rewriting a JSON blob.

> **Do not paste secrets on the command line.** `--value '<new>'` lands the
> credential in `~/.zsh_history` (and in the process list while it runs). Read it
> from a mode-600 file instead and delete the file afterwards, or rotate in the
> AWS console.

```bash
umask 077 && printf '%s' '<new>' > /tmp/rot.$$   # not world-readable
aws ssm put-parameter --name /mqsmaster-prod/db/password \
  --type SecureString --value "file:///tmp/rot.$$" --overwrite
shred -u /tmp/rot.$$ 2>/dev/null || rm -P /tmp/rot.$$
```

The parameter keeps whatever KMS key it was created with, so `--key-id` is not
needed on rotation. It is only required when **changing** the key — the default
is the AWS-managed `alias/aws/ssm`; pass the CMK explicitly if the module's
`kms_key_id` has been pointed at a customer managed key:

```bash
aws ssm put-parameter --name /mqsmaster-prod/db/password \
  --type SecureString --key-id 'alias/mqsmaster-prod' \
  --value "file:///tmp/rot.$$" --overwrite
```

List what exists (metadata only, no values):

```bash
aws ssm describe-parameters --parameter-filters 'Key=Path,Option=Recursive,Values=/mqsmaster-prod'
```

**Alternative: re-seed from Terraform.** Edit the value in `terraform.tfvars`,
then bump the matching version counter in the same file — editing the value alone
does nothing, because Terraform cannot see it:

```hcl
db_secret_values     = { ... }   # new password here
db_parameter_version = 2         # <- without this bump, apply is a no-op
```

`terraform.tfvars` holds live credentials in plaintext. It is gitignored
(`.gitignore:5`) and must stay that way; keep it mode 600 and never copy it into
a shared location. Only `terraform.tfvars.example`, which contains placeholders,
is tracked.

Bumping `db_parameter_version` rewrites **all six** `/db/*` parameters **and the
RDS master password** — they share the counter deliberately, so the database and
the credential the containers read cannot drift apart. `api_parameter_version`
covers the three `/api/*` keys. Either way the whole group is rewritten,
discarding out-of-band rotations of the others, so prefer `put-parameter` when
rotating a single credential.

This is also the mechanism for fixing `/mqsmaster-prod/db/host` if RDS is ever
replaced and gets a new endpoint — bump `db_parameter_version` and apply.

Secrets are read at task start, so a rotation reaches the container at the next
scheduled run. There is no ECS Service to `--force-new-deployment` — the stack
runs only the scheduled market task.

A session already in flight keeps the old value for its whole run. If the
rotation has to land immediately, stop the running task and re-trigger it by
hand (see [Manually trigger the market task](#manually-trigger-the-market-task)),
accepting that the session restarts from scratch:

```bash
aws ecs stop-task --cluster mqsmaster-prod-cluster --task <task-arn> --reason "credential rotation"
```

## Changing the schedule

Override in `terraform.tfvars`:

```hcl
schedule_expression    = "cron(0 11 ? * MON-FRI *)"
schedule_timezone      = "America/St_Johns"
use_scheduler_timezone = true
```

**Do not move this earlier than the market open.** `start.sh` evaluates
`is_market_open` on the first iteration of its monitor loop, immediately after
launching the market scripts — if the market is not open yet it SIGTERMs all of
them and exits. 11:00 `America/St_Johns` is the 09:30 ET open, since Newfoundland
runs ET+1:30.

## Adding a new environment

The layout supports it without touching module code.

Copy the **tracked** files only — never `cp -r`. The live directory also holds
`terraform.tfvars`, `terraform.tfstate`, and `.terraform/`, all gitignored; a
recursive copy would clone live credentials and live state into the new
environment.

```bash
mkdir -p terraform/environments/staging
git -C terraform/environments/Livetrading ls-files -z \
  | xargs -0 -I{} cp terraform/environments/Livetrading/{} terraform/environments/staging/{}

# start staging's tfvars from the placeholders, not from the live file
cp terraform/environments/staging/terraform.tfvars.example \
   terraform/environments/staging/terraform.tfvars
chmod 600 terraform/environments/staging/terraform.tfvars
# edit staging/terraform.tfvars: environment = "staging", smaller sizing, and
# credentials issued for staging — do not reuse the live ones
```

**Then change the workspace name — this step is not optional.** The copy brings
`terraform.tf` with it, and that file hardcodes
`cloud { workspaces { name = "MQS_AWS_INFRA_LIVE" } }`. Left as-is, the new
directory binds to **production state**, and its first plan reads staging's
smaller sizing out of `terraform.tfvars` and proposes modifying the live RDS
instance and ECS services. Create a new workspace and point the copy at it:

```bash
# in staging/terraform.tf
#   workspaces { name = "MQS_AWS_INFRA_STAGING" }
```

Only after that does each environment keep its own state and `terraform.tfvars`
— one workspace holds one state, so the binding is what separates them, not the
directory. Module sources (`../../modules/Livetrading/...`) resolve identically
from any environment directory.
