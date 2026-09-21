resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.name}"
  retention_in_days = 14
}

resource "aws_codebuild_project" "web" {
  name         = "${var.name}-web"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-web.yml"
  }
}

resource "aws_codebuild_project" "app" {
  name         = "${var.name}-app"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-app.yml"
  }
}

resource "aws_codedeploy_app" "web" {
  name             = "${var.name}-web"
  compute_platform = "Server"
}

resource "aws_codedeploy_app" "app" {
  name             = "${var.name}-app"
  compute_platform = "Server"
}

resource "aws_codedeploy_deployment_group" "web" {
  app_name                    = aws_codedeploy_app.web.name
  deployment_group_name       = "${var.name}-web"
  service_role_arn            = aws_iam_role.codedeploy.arn
  deployment_config_name      = "CodeDeployDefault.OneAtATime"
  autoscaling_groups          = [aws_autoscaling_group.web.name]
  outdated_instances_strategy = "UPDATE"

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.web.name
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}

resource "aws_codedeploy_deployment_group" "app" {
  app_name                    = aws_codedeploy_app.app.name
  deployment_group_name       = "${var.name}-app"
  service_role_arn            = aws_iam_role.codedeploy.arn
  deployment_config_name      = "CodeDeployDefault.OneAtATime"
  autoscaling_groups          = [aws_autoscaling_group.app.name]
  outdated_instances_strategy = "UPDATE"

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app.name
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}

resource "aws_codepipeline" "app" {
  name           = var.name
  pipeline_type  = "V2"
  execution_mode = "QUEUED"
  role_arn       = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repository
        BranchName           = var.github_branch
        DetectChanges        = "true"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Web"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["WebArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.web.name
      }
    }

    action {
      name             = "App"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["AppArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.app.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Web"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["WebArtifact"]
      run_order       = 1

      configuration = {
        ApplicationName     = aws_codedeploy_app.web.name
        DeploymentGroupName = aws_codedeploy_deployment_group.web.deployment_group_name
      }
    }

    action {
      name            = "App"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["AppArtifact"]
      run_order       = 2

      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.app.deployment_group_name
      }
    }
  }
}