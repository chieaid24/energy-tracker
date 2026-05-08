# ---------- Cluster ----------
output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}

# ---------- Networking ----------
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

# ---------- RDS ----------
output "rds_endpoint" {
  value       = module.rds.db_instance_address
  description = "RDS MySQL endpoint hostname (use port 3306)"
}

output "rds_jdbc_url" {
  value = "jdbc:mysql://${module.rds.db_instance_endpoint}/${var.rds_database_name}"
}

output "rds_database" {
  value = var.rds_database_name
}

output "rds_secret_arn" {
  value       = aws_secretsmanager_secret.rds_password.arn
  description = "Secrets Manager ARN holding RDS master credentials"
}

# ---------- MSK ----------
output "msk_cluster_arn" {
  value = aws_msk_serverless_cluster.this.arn
}

output "msk_bootstrap_brokers" {
  value       = aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam
  description = "Kafka SASL/IAM bootstrap broker endpoints"
}

# ---------- IRSA roles ----------
output "irsa_role_arns" {
  value = {
    ebs_csi          = module.ebs_csi_irsa.iam_role_arn
    alb_controller   = module.alb_controller_irsa.iam_role_arn
    external_dns     = module.external_dns_irsa.iam_role_arn
    cert_manager     = module.cert_manager_irsa.iam_role_arn
    external_secrets = module.external_secrets_irsa.iam_role_arn
    insight_service  = module.insight_service_irsa.iam_role_arn
    gha_deploy       = aws_iam_role.gha_deploy.arn
  }
  description = "IAM role ARNs for IRSA-bound ServiceAccounts and CI/CD"
}

# ---------- DNS / TLS (only when domain_apex is set) ----------
output "route53_zone_id" {
  value = var.domain_apex != "" ? aws_route53_zone.this[0].zone_id : null
}

output "route53_zone_name_servers" {
  value       = var.domain_apex != "" ? aws_route53_zone.this[0].name_servers : null
  description = "Delegate these NS records from the parent zone"
}

output "acm_cert_arn" {
  value = var.domain_apex != "" ? aws_acm_certificate.this[0].arn : null
}

output "ingress_hostname" {
  value = var.domain_apex != "" ? "${var.domain_subdomain}.${var.domain_apex}" : null
}
