resource "random_password" "rds" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL access from EKS nodes only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "MySQL from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.10"

  identifier = "${local.name_prefix}-mysql"

  engine               = "mysql"
  engine_version       = var.rds_engine_version
  family               = "mysql8.0"
  major_engine_version = "8.0"
  instance_class       = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = 100
  storage_encrypted     = true

  db_name                     = var.rds_database_name
  username                    = var.rds_master_username
  password                    = random_password.rds.result
  manage_master_user_password = false

  multi_az               = false
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  parameters = [
    { name = "character_set_server", value = "utf8mb4" },
    { name = "collation_server", value = "utf8mb4_unicode_ci" },
  ]

  skip_final_snapshot          = true
  deletion_protection          = false
  performance_insights_enabled = true

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "rds_password" {
  name                    = "iot/${var.env}/rds/master"
  description             = "RDS master credentials for IoT Energy Tracker"
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    username = var.rds_master_username
    password = random_password.rds.result
    host     = module.rds.db_instance_address
    port     = module.rds.db_instance_port
    database = var.rds_database_name
    jdbc_url = "jdbc:mysql://${module.rds.db_instance_endpoint}/${var.rds_database_name}"
  })
}
