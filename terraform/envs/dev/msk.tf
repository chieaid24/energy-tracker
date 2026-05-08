resource "aws_security_group" "msk" {
  name        = "${local.name_prefix}-msk-sg"
  description = "MSK Serverless access from EKS nodes (IAM SASL on 9098)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "Kafka IAM SASL from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_msk_serverless_cluster" "this" {
  cluster_name = "${local.name_prefix}-msk"

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.msk.id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  tags = local.common_tags
}

# MSK Serverless ARN format:
#   arn:aws:kafka:<region>:<account>:cluster/<name>/<uuid>
# Topic / group ARNs reuse the same suffix, swapping "cluster" for "topic" / "group".
locals {
  msk_arn_parts  = split("/", aws_msk_serverless_cluster.this.arn)
  msk_arn_suffix = "${local.msk_arn_parts[1]}/${local.msk_arn_parts[2]}"
  msk_topic_arn  = "arn:aws:kafka:${var.region}:${data.aws_caller_identity.current.account_id}:topic/${local.msk_arn_suffix}/*"
  msk_group_arn  = "arn:aws:kafka:${var.region}:${data.aws_caller_identity.current.account_id}:group/${local.msk_arn_suffix}/*"
}

data "aws_iam_policy_document" "msk_full_access" {
  statement {
    sid    = "ClusterConnect"
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:AlterCluster",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:DescribeClusterDynamicConfiguration",
    ]
    resources = [aws_msk_serverless_cluster.this.arn]
  }

  statement {
    sid    = "TopicReadWrite"
    effect = "Allow"
    actions = [
      "kafka-cluster:CreateTopic",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:DescribeTopicDynamicConfiguration",
      "kafka-cluster:AlterTopic",
      "kafka-cluster:AlterTopicDynamicConfiguration",
      "kafka-cluster:DeleteTopic",
      "kafka-cluster:WriteData",
      "kafka-cluster:ReadData",
    ]
    resources = [local.msk_topic_arn]
  }

  statement {
    sid    = "ConsumerGroup"
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup",
      "kafka-cluster:DeleteGroup",
    ]
    resources = [local.msk_group_arn]
  }
}

resource "aws_iam_policy" "msk_full_access" {
  name        = "${local.name_prefix}-msk-full-access"
  description = "MSK IAM auth for IoT services (Kafka producer/consumer)"
  policy      = data.aws_iam_policy_document.msk_full_access.json
  tags        = local.common_tags
}

# Attach to the managed-node-group instance role for now. Tighter scoping (per-service
# IRSA) is a follow-up — covered in Phase 8 hardening.
resource "aws_iam_role_policy_attachment" "node_msk" {
  role       = module.eks.eks_managed_node_groups["main"].iam_role_name
  policy_arn = aws_iam_policy.msk_full_access.arn
}
