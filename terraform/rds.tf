resource "random_password" "rds" {
  length           = 24
  special          = true
  override_special = "-_!#%^"
}

resource "aws_secretsmanager_secret" "rds" {
  name = "${var.name}/rds/master"
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = "appadmin"
    password = random_password.rds.result
    engine   = "mysql"
    port     = 3306
  })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-rds"
  subnet_ids = [for s in aws_subnet.data : s.id]
}

resource "aws_db_instance" "mysql" {
  identifier              = "${var.name}-mysql"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_encrypted       = true
  db_name                 = "app"
  username                = "appadmin"
  password                = random_password.rds.result
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = true
  publicly_accessible     = false
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
}
