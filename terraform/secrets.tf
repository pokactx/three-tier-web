resource "random_password" "session" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name = "${var.name}/app/runtime"
}

# 初期値だけ Terraform が入れる。以降のローテは ignore_changes。
resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    SESSION_SECRET      = random_password.session.result
    THIRD_PARTY_API_KEY = "replace-me-outside-terraform"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
