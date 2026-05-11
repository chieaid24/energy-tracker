# ---------- IRSA roles for in-cluster controllers ----------

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name             = "${local.name_prefix}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                              = "${local.name_prefix}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                     = "${local.name_prefix}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = var.domain_apex != "" ? [aws_route53_zone.this[0].arn] : ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }

  tags = local.common_tags
}

module "cert_manager_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                     = "${local.name_prefix}-cert-manager"
  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = var.domain_apex != "" ? [aws_route53_zone.this[0].arn] : ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }

  tags = local.common_tags
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                      = "${local.name_prefix}-external-secrets"
  attach_external_secrets_policy = true

  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:iot/${var.env}/*",
  ]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = local.common_tags
}

# ---------- IRSA for insight-service (Bedrock invoke) ----------

data "aws_iam_policy_document" "bedrock_invoke" {
  # Inference-profile invoke. The us.* profile is the entry point insight-service
  # actually calls; AWS Bedrock then routes execution to one of the foundation-model
  # ARNs in the second statement.
  statement {
    sid    = "BedrockInvokeInferenceProfile"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]
    resources = [
      "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-haiku-4-5-*",
      # Keep Haiku 3.5 and Sonnet 4.5 profiles available so we can flip via env var
      # without re-applying Terraform.
      "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-sonnet-4-5-*",
    ]
  }

  # Foundation-model invoke across every region a us.* profile may route to.
  # The 'us.' inference profile fans out to us-east-1, us-east-2, us-west-2 — each
  # region needs its own IAM grant on the underlying foundation-model ARN.
  statement {
    sid    = "BedrockInvokeFoundationModels"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]
    resources = [
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-haiku-4-5-*",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-haiku-4-5-*",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-haiku-4-5-*",
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-5-*",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-sonnet-4-5-*",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-5-*",
    ]
  }
}

resource "aws_iam_policy" "bedrock_invoke" {
  name        = "${local.name_prefix}-bedrock-invoke"
  description = "Allow insight-service to invoke Bedrock foundation models"
  policy      = data.aws_iam_policy_document.bedrock_invoke.json
  tags        = local.common_tags
}

module "insight_service_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name = "${local.name_prefix}-insight-service"
  role_policy_arns = {
    bedrock = aws_iam_policy.bedrock_invoke.arn
  }

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      # ServiceAccount name must match what microservices-chart renders.
      namespace_service_accounts = ["default:microservices-insight-service"]
    }
  }

  tags = local.common_tags
}

# ---------- GitHub Actions OIDC provider + deploy role ----------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

data "aws_iam_openid_connect_provider" "github_existing" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github_existing[0].arn
}

data "aws_iam_policy_document" "gha_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:ref:refs/tags/v*",
        "repo:${var.github_repo}:environment:${var.env}",
      ]
    }
  }
}

data "aws_iam_policy_document" "gha_deploy" {
  statement {
    sid    = "ECRPublic"
    effect = "Allow"
    actions = [
      "ecr-public:GetAuthorizationToken",
      "ecr-public:BatchCheckLayerAvailability",
      "ecr-public:PutImage",
      "ecr-public:InitiateLayerUpload",
      "ecr-public:UploadLayerPart",
      "ecr-public:CompleteLayerUpload",
      "ecr-public:DescribeRepositories",
      "sts:GetServiceBearerToken",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EKSAccess"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_role" "gha_deploy" {
  name               = "${local.name_prefix}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "deploy"
  role   = aws_iam_role.gha_deploy.id
  policy = data.aws_iam_policy_document.gha_deploy.json
}
