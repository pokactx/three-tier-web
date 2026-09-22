# 情シス用の踏み台。非公開サブネット、公開 IP なし。SSM は NAT 経由（VPC エンドポイントは使わない）。
# RDS の 3306 はこの SG だけ追加で開ける。アプリ用マスターをインスタンスに置かない。

resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion"
  description = "Private SSM bastion"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-sg-bastion" }
}

resource "aws_security_group_rule" "bastion_egress_https" {
  type              = "egress"
  description       = "SSM and package updates via NAT"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "bastion_egress_rds" {
  type                     = "egress"
  description              = "MySQL to RDS primary"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "rds_ingress_bastion" {
  type                     = "ingress"
  description              = "MySQL from SSM bastion"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.rds.id
}

resource "aws_iam_role" "bastion" {
  name               = "${var.name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "bastion_session_logs" {
  role       = aws_iam_role.bastion.name
  policy_arn = aws_iam_policy.session_logs.arn
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-bastion"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.app["a"].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${var.name}-bastion" }

  lifecycle {
    ignore_changes = [ami]
  }
}
