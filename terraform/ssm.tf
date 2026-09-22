resource "aws_cloudwatch_log_group" "session" {
  name              = "/${var.name}/session-manager"
  retention_in_days = 30
}

data "aws_iam_policy_document" "session_logs" {
  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.session.arn,
      "${aws_cloudwatch_log_group.session.arn}:*",
    ]
  }
}

resource "aws_iam_policy" "session_logs" {
  name   = "${var.name}-session-logs"
  policy = data.aws_iam_policy_document.session_logs.json
}

resource "aws_iam_role_policy_attachment" "web_session_logs" {
  role       = aws_iam_role.web.name
  policy_arn = aws_iam_policy.session_logs.arn
}

resource "aws_iam_role_policy_attachment" "app_session_logs" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.session_logs.arn
}

# リージョンの Session Manager 既定。Web / App / 踏み台のシェルが CloudWatch に残る。
resource "aws_ssm_document" "session" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences"
    sessionType   = "Standard_Stream"
    inputs = {
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.session.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      runAsEnabled                = false
    }
  })
}
