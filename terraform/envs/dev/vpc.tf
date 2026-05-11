module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs              = local.azs
  public_subnets   = ["10.20.0.0/20", "10.20.16.0/20", "10.20.32.0/20"]
  private_subnets  = ["10.20.64.0/20", "10.20.80.0/20", "10.20.96.0/20"]
  database_subnets = ["10.20.128.0/24", "10.20.129.0/24", "10.20.130.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.common_tags
}

# S3 gateway endpoint is free and avoids NAT cost for ECR layer pulls.
# Interface endpoints (ECR API, Secrets Manager, STS) are deferred — each adds ~$8/mo.
module "vpc_s3_endpoint" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.13"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.database_route_table_ids)
      tags            = { Name = "${local.name_prefix}-s3-vpce" }
    }
  }

  tags = local.common_tags
}
