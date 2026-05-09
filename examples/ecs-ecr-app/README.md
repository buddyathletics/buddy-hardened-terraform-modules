# `examples/ecs-ecr-app` — Hardened public frontend + private API

This example wires both modules into the canonical Buddy app shape:

- **Two ECS services in one Service Connect namespace**
  - `frontend` — public via the shared ALB target group; client-only Service Connect participant
  - `api` — internal-only (no target group); registers as `api:<port>` so the frontend's nginx can `proxy_pass http://api:<port>/`
- **Two ECR repos** (one per service) with environment-correct lifecycle profiles
- **One SSM SecureString placeholder** for `DATABASE_URL` — populated out-of-band; the API's task execution role gets `ssm:GetParameters` automatically
- **Default CloudWatch alarm set** on both services, optionally fanned out to a shared SNS topic for Slack delivery

This composition serves as the **contract test** for the `ecs-app` and `ecr-repository` modules: any change that breaks the two-service shape gets caught by `terraform validate` in CI before it ships.

## Defense-in-depth (what stops an attacker from hitting the API directly?)

Reachability is enforced by **security groups**, not by Service Connect — Service Connect is a discovery + load-balancing layer, it doesn't open ports. The layers, in order:

1. **No public DNS for the API.** Only the frontend hostname has a Cloudflare record; nothing resolves to the API.
2. **No ALB target for the API.** `target_group_arn = null` on the API module call. Even with a guessed hostname, the shared ALB has no rule that forwards to the API.
3. **API SG ingress = `[frontend.security_group_id]` on the API's container_port.** Lateral movement from any other container in the cluster is blocked at the SG layer.
4. **Frontend SG ingress = `[shared_alb_security_group_id]` on `frontend_container_port`.** The frontend itself is reachable only from the ALB.
5. **Service Connect namespace scoping.** The alias `api:<port>` is only resolvable inside this app's namespace; siblings in other apps' namespaces get NXDOMAIN.

## Service Connect: client-mode vs server-mode

The module's `service_connect_*` inputs distinguish two roles:

| Inputs | Effect | Used by |
| --- | --- | --- |
| `service_connect_namespace_arn = X` only | **Client mode**: task joins the mesh, gets the Envoy sidecar, can resolve sibling aliases. Not discoverable by name itself. | frontend in this example |
| `service_connect_namespace_arn = X` + `service_connect_port_alias = "api"` | **Client + server**: above, plus registers itself as `api:<port>` so siblings can call it. | API in this example |

The frontend is deliberately client-only — nothing inside the namespace ever calls back into the frontend (public traffic comes through the ALB), so we don't publish a `frontend:80` alias. Less surface area, no functional difference.

## Inputs you must provide

The example reads the VPC, subnets, and ECS cluster from `data.terraform_remote_state.shared` (matching the existing `buddy-shared-infrastructure` outputs). The shared ALB's listener ARN, its security group ID, and the alarm SNS topic ARN are passed in directly until shared-infra Phase B exports them via remote state — once it does, consumers can replace those variables with `data.terraform_remote_state.shared.outputs.<name>` at the call site.

```hcl
module "admin_dev" {
  source = "git::https://github.com/buddyathletics/buddy-hardened-terraform-modules.git//examples/ecs-ecr-app?ref=v0.3.0"

  app_name_prefix         = "buddyMVP-Admin"
  repository_name_prefix  = "buddyMVP-Admin"
  environment             = "dev"

  shared_state_bucket = "buddy-athletics-terraform-state-bucket"
  shared_state_key    = "networking/dev/terraform.tfstate"

  shared_https_listener_arn    = "arn:aws:elasticloadbalancing:us-east-1:643025068953:listener/app/buddy-athletics-dev/.../..."
  shared_alb_security_group_id = "sg-..."
  alarm_sns_topic_arn          = "arn:aws:sns:us-east-1:643025068953:buddy-athletics-alerts-dev"

  frontend_hostname      = "admin-dev.buddyathletics.com"
  listener_rule_priority = 100   # admin=100, host=110, facility=120, user=130
}
```

## Operator runbook (one-time, per environment)

After the first `terraform apply`, populate the SSM SecureString:

```bash
export AWS_PROFILE=buddy-athletics

aws ssm put-parameter --overwrite \
  --name /buddyMVP-Admin/dev/DATABASE_URL \
  --type SecureString \
  --value 'postgresql+asyncpg://buddy_admin_app:<password>@ep-XXX-pooler.us-east-1.aws.neon.tech/buddy_admin?sslmode=require'

aws ecs update-service \
  --cluster buddy-athletics-dev-cluster \
  --service buddyMVP-Admin-api-dev-service \
  --force-new-deployment
```

The connection string never leaves your laptop and SSM. Rotation is the same two commands — no GitHub change, no Terraform change, no image rebuild.
