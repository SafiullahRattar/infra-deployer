# --- DB Subnet Group ---

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}

# --- Security Group ---

resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-"
  vpc_id      = var.vpc_id
  description = "Security group for RDS PostgreSQL instance"

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name_prefix}-rds-sg"
  }
}

# --- Parameter Group ---

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.name_prefix}-pg-"
  family      = "postgres16"
  description = "Custom parameter group for ${var.name_prefix}"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name_prefix}-pg"
  }
}

# --- RDS Instance ---

resource "aws_db_instance" "main" {
  identifier = "${var.name_prefix}-db"

  engine         = "postgres"
  engine_version = "16.4"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az            = false
  publicly_accessible = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"

  deletion_protection       = var.enable_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-db-final-snapshot"

  performance_insights_enabled = true

  tags = {
    Name = "${var.name_prefix}-db"
  }
}
