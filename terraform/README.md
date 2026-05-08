# Terraform — IoT Energy Tracker AWS infrastructure

Infrastructure-as-code for the EKS-based deployment. Docker Compose and Minikube setups in the rest of this repo are unaffected.

> **Phase gating**: this Terraform is **Phase 1** of the EKS migration tracked in `eks_plan.md`. After the Phase 1 final gate (validation checklist below) the operator/agent must STOP and wait for explicit approval before starting Phase 2. Same rule applies at every subsequent phase boundary. Sub-phases (1A, 1B, …) flow without waiting; only inter-phase boundaries require approval.

> **Current state**: code complete, **not applied**. `terraform init` + `terraform validate` pass. `terraform apply` is the next destructive step and requires explicit user go-ahead. AWS account `714454206433`, region `us-east-1`. Domain `energy.aidanchien.com` (apex `aidanchien.com` stays at Porkbun — NS delegation happens after `apply`).

## Layout

```
terraform/
  envs/
    dev/             # development environment (single root module)
      versions.tf    # terraform & provider version constraints
      providers.tf   # AWS provider config + global data sources
      variables.tf   # input variables
      locals.tf      # derived values (name prefix, common tags)
      vpc.tf         # VPC, subnets, NAT, S3 endpoint
      eks.tf         # EKS cluster + node group + access entries
      iam.tf         # IRSA roles + GitHub Actions deploy role
      rds.tf         # MySQL 8 RDS instance + Secrets Manager wiring
      msk.tf         # MSK Serverless cluster + node IAM policy
      dns.tf         # Route53 zone + ACM cert (gated on domain_apex)
      outputs.tf     # outputs consumed by Helm/CI
      terraform.tfvars.example
      .gitignore
```

State is local-only for now (`.tfstate` in this directory, gitignored). Move to S3 + DynamoDB lock once the cluster is stable — see "Remote state" below.

## Prerequisites

- Terraform >= 1.5 (`tfenv install latest`)
- AWS CLI v2 with credentials: `aws configure` then `aws sts get-caller-identity` to confirm
- Bedrock model access enabled for `anthropic.claude-haiku-4-5-20251001-v1:0` in `us-east-1` (Bedrock console → Model access → Manage). Haiku 4.5 only invokes via the cross-region inference profile `us.anthropic.claude-haiku-4-5-...`, never as a direct on-demand call. The Terraform IAM policy already grants invoke on the profile + the foundation-model ARN in us-east-1, us-east-2, and us-west-2 (the regions that profile fans out to)
- **Bedrock per-day token quota verified non-zero.** New AWS accounts often have model access granted but `Model invocation max tokens per day for Anthropic Claude Haiku 4.5` set to 0, which blocks every invocation regardless of model. Submit a Service Quotas request for `Cross-region model inference tokens per minute for Anthropic Claude Haiku 4.5` (any value at-or-below the 5,000,000 default; AWS auto-approves). That request triggers an account-level review which also lifts the daily cap. Phases 1–6 can complete without this; Phase 7's `/api/v1/insight` smoke test will fail until quota lands

## First-time apply

```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set domain_apex, allowed_admin_cidrs

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Expect ~20–25 minutes the first time (EKS + RDS dominate). Subsequent applies are fast.

## After apply

```bash
# Configure kubectl
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region $(terraform output -raw region)

# Sanity checks
kubectl get nodes
kubectl get pods -A

# Verify outputs you'll need for Helm overlays
terraform output rds_jdbc_url
terraform output msk_bootstrap_brokers
terraform output irsa_role_arns
terraform output ingress_hostname
```

If `domain_apex` is set, copy the `route53_zone_name_servers` output into the parent zone (your registrar) as NS records for the subdomain.

## Phase 1 validation checklist

Run after `terraform apply` finishes — these match the gates in `eks_plan.md`:

- [ ] `kubectl get nodes` shows 2+ nodes Ready
- [ ] `kubectl get pods -n kube-system` — all Running
- [ ] `aws rds describe-db-instances --db-instance-identifier iot-tracker-dev-mysql --query 'DBInstances[0].DBInstanceStatus'` returns `available`
- [ ] `aws kafka list-clusters-v2 --query 'ClusterInfoList[?ClusterName==`iot-tracker-dev-msk`].State'` returns `ACTIVE`
- [ ] `aws acm describe-certificate --certificate-arn $(terraform output -raw acm_cert_arn) --query 'Certificate.Status'` returns `ISSUED` (only if domain configured)
- [ ] `terraform output irsa_role_arns` lists all 7 ARNs

## Remote state (defer)

Once the cluster is up and you've validated, migrate state:

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "iot-tracker-tfstate-<account-id>"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "iot-tracker-tfstate-lock"
    encrypt        = true
  }
}
```

Then `terraform init -migrate-state`.

## Tearing down

```bash
terraform destroy
```

⚠️ This deletes RDS + MSK + EKS. Make sure no production data lives here.

## Cost estimate (dev)

Rough monthly burn at idle, us-east-1:

| Component | ~Monthly |
|---|---|
| EKS control plane | $73 |
| 2 × t3.large on-demand | $120 |
| 1 × NAT gateway + traffic | $35 |
| RDS db.t3.medium + 20Gi gp3 | $75 |
| MSK Serverless (idle) | $40 |
| EBS volumes (PVCs from Helm) | $10–20 |
| Route53 zone + queries | $1 |
| **Total** | **~$355/mo** |

Bedrock is pay-per-token and only billed when `insight-service` is invoked. Set a budget alarm before applying.
