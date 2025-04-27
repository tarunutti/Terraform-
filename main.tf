# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "aurora-vpc"
  }
}

# Create Private Subnets
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"

  tags = {
    Name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}b"

  tags = {
    Name = "private-subnet-b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "aurora-igw"
  }
}

# Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "aurora-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Group
resource "aws_security_group" "aurora_sg" {
  name        = "${var.cluster_identifier}-sg"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  tags = {
    Name = "aurora-db-subnet-group"
  }
}

# Create a Secret for Credentials
resource "aws_secretsmanager_secret" "rds_credentials" {
  name = "${var.cluster_identifier}-credentials"
}

resource "aws_secretsmanager_secret_version" "rds_credentials_version" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
    engine   = "postgres"
    port     = 5432
    dbname   = var.database_name
  })
}

# RDS Parameter Group (pgvector setup)
resource "aws_rds_cluster_parameter_group" "aurora_pg_parameters" {
  name        = "${var.cluster_identifier}-param-group"
  family      = var.parameter_group_family
  description = "Custom param group for Aurora PostgreSQL"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pgvector"
    apply_method = "pending-reboot"
  }
}

# Aurora RDS Cluster
resource "aws_rds_cluster" "aurora_postgresql" {
  cluster_identifier             = var.cluster_identifier
  engine                         = "aurora-postgresql"
  engine_version                 = var.engine_version
  database_name                  = var.database_name
  master_username                = var.master_username
  master_password                = var.master_password
  storage_encrypted              = true
  db_subnet_group_name           = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids         = [aws_security_group.aurora_sg.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_pg_parameters.name
  deletion_protection            = var.deletion_protection_enabled

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1.0
  }

  lifecycle {
    ignore_changes = [master_password]
  }
}

# Writer Instance
resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier = aws_rds_cluster.aurora_postgresql.id
  instance_class     = var.instance_type
  engine             = aws_rds_cluster.aurora_postgresql.engine
  engine_version     = aws_rds_cluster.aurora_postgresql.engine_version
  identifier         = "${var.cluster_identifier}-writer"
  availability_zone  = "${var.region}a"
  promotion_tier     = 0
}

# Read Replicas
resource "aws_rds_cluster_instance" "read_replicas" {
  count = 2

  cluster_identifier = aws_rds_cluster.aurora_postgresql.id
  instance_class     = var.instance_type
  engine             = aws_rds_cluster.aurora_postgresql.engine
  engine_version     = aws_rds_cluster.aurora_postgresql.engine_version
  identifier         = "${var.cluster_identifier}-replica-${count.index}"
  availability_zone  = "${var.region}${count.index == 0 ? "b" : "c"}"
  promotion_tier     = 1
}

# IAM Role for RDS Proxy
resource "aws_iam_role" "rds_proxy_role" {
  name = "${var.cluster_identifier}-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rds_proxy_policy" {
  name = "${var.cluster_identifier}-proxy-policy"
  role = aws_iam_role.rds_proxy_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.rds_credentials.arn
      }
    ]
  })
}

# RDS Proxy
resource "aws_db_proxy" "rds_proxy" {
  name                   = "${var.cluster_identifier}-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_subnet_ids         = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]

  auth {
    auth_scheme = "SECRETS"
    description = "Auth through Secrets Manager"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.rds_credentials.arn
  }

  tags = {
    Name = "${var.cluster_identifier}-proxy"
  }
}

resource "aws_db_proxy_default_target_group" "default" {
  db_proxy_name = aws_db_proxy.rds_proxy.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_target" {
  db_proxy_name         = aws_db_proxy.rds_proxy.name
  target_group_name     = aws_db_proxy_default_target_group.default.name
  db_cluster_identifier = aws_rds_cluster.aurora_postgresql.id
}
