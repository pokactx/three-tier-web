resource "aws_security_group" "alb_public" {
  name                   = "${var.name}-alb-public"
  description            = "Internet-facing ALB"
  vpc_id                 = aws_vpc.this.id
  revoke_rules_on_delete = true

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-sg-alb-public" }
}

resource "aws_security_group_rule" "alb_public_ingress_cloudfront_http" {
  type              = "ingress"
  description       = "HTTP from CloudFront origin-facing IPs"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb_public.id
}

resource "aws_security_group" "web" {
  name        = "${var.name}-web"
  description = "Private web ASG"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-sg-web" }
}

resource "aws_security_group_rule" "web_ingress_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public.id
  security_group_id        = aws_security_group.web.id
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Private app ASG"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-sg-app" }
}

resource "aws_security_group_rule" "app_ingress_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public.id
  security_group_id        = aws_security_group.app.id
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS MySQL; app to primary only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-sg-rds" }
}

resource "aws_security_group_rule" "rds_ingress_app" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.rds.id
}
