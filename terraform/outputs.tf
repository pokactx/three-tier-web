output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_alb_dns" {
  value = aws_lb.public.dns_name
}

output "rds_primary_address" {
  value = aws_db_instance.mysql.address
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.rds.arn
}

output "static_bucket" {
  value = aws_s3_bucket.static.bucket
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.static.domain_name
}

output "waf_acl_arn" {
  value = aws_wafv2_web_acl.edge.arn
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "app_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "github_connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "pipeline_name" {
  value = aws_codepipeline.app.name
}
