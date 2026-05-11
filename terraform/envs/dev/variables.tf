variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "project" {
  type        = string
  default     = "iot-tracker"
  description = "Project tag prefix used in resource names"
}

variable "env" {
  type        = string
  default     = "dev"
  description = "Environment name (dev, staging, prod)"
}

variable "cluster_name" {
  type        = string
  default     = "iot-tracker-dev"
  description = "EKS cluster name"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.31"
  description = "EKS Kubernetes minor version"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.20.0.0/16"
  description = "VPC CIDR block"
}

variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.large"]
  description = "EC2 instance types for the main managed node group"
}

variable "node_group_desired_size" {
  type    = number
  default = 2
}

variable "node_group_max_size" {
  type    = number
  default = 4
}

variable "node_group_min_size" {
  type    = number
  default = 2
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "rds_engine_version" {
  type        = string
  default     = "8.0.39"
  description = "RDS MySQL engine version"
}

variable "rds_allocated_storage" {
  type        = number
  default     = 20
  description = "Initial RDS storage in GiB. max_allocated_storage allows autogrowth."
}

variable "rds_database_name" {
  type    = string
  default = "energy_tracker"
}

variable "rds_master_username" {
  type    = string
  default = "iotadmin"
}

variable "github_repo" {
  type        = string
  default     = "chieaid24/IoT-Energy-Tracker"
  description = "owner/repo for GitHub Actions OIDC trust"
}

variable "create_github_oidc_provider" {
  type        = bool
  default     = true
  description = "Create the GitHub Actions OIDC provider. Set to false if your account already has one."
}

variable "domain_apex" {
  type        = string
  default     = ""
  description = "Apex domain (e.g. example.com). If empty, Route53/ACM resources are skipped."
}

variable "domain_subdomain" {
  type        = string
  default     = "iot"
  description = "Subdomain prefix used for ingress (e.g. 'iot' -> iot.example.com)"
}

variable "allowed_admin_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the EKS public endpoint. Restrict for production."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged into the default tag set"
}
