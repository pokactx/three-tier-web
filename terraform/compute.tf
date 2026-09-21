data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_lb" "public" {
  name               = "${var.name}-public"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb_public.id]
  subnets            = [for s in aws_subnet.public : s.id]

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_lb_target_group" "web" {
  name     = "${var.name}-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb_target_group" "app" {
  # TG は LB 1 台にしか付けられない。内部 ALB 用 midsize-app とは別名にする。
  name     = "${var.name}-api"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path    = "/health"
    matcher = "200"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "public" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "public_api" {
  listener_arn = aws_lb_listener.public.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }

  condition {
    path_pattern {
      values = ["/api", "/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "public_web" {
  listener_arn = aws_lb_listener.public.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.name}-web-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.web_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.web.name
  }

  vpc_security_group_ids = [aws_security_group.web.id]
  user_data = base64encode(templatefile("${path.module}/templates/web.sh.tftpl", {
    region = var.region
  }))

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-web" }
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-app-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.app_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]
  user_data = base64encode(templatefile("${path.module}/templates/app.sh.tftpl", {
    region         = var.region
    upload_bucket  = aws_s3_bucket.static.bucket
    rds_primary    = aws_db_instance.mysql.address
    rds_secret_arn = aws_secretsmanager_secret.rds.arn
    app_secret_arn = aws_secretsmanager_secret.app.arn
  }))

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-app" }
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "${var.name}-web"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  vpc_zone_identifier       = [for s in aws_subnet.web : s.id]
  health_check_type         = "ELB"
  health_check_grace_period = 180
  target_group_arns         = [aws_lb_target_group.web.arn]
  service_linked_role_arn   = data.aws_iam_role.autoscaling.arn

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-web"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.name}-app"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  vpc_zone_identifier       = [for s in aws_subnet.app : s.id]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.app.arn]
  service_linked_role_arn   = data.aws_iam_role.autoscaling.arn

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-app"
    propagate_at_launch = true
  }
}
