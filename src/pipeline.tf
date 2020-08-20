# CodeBuildプロジェクト
resource "aws_codebuild_project" "tech-blog" {
  name         = "tech-blog"
  service_role = module.codebuild_role.iam_role_arn

  # ビルド対象のソースをCodePipelineと連携する宣言
  source {
    type = "CODEPIPELINE"
  }

  # ビルド出力アーティファクトの格納先をCodePipelineと連携する宣言
  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:2.0"
    # ビルド時にdocker コマンドを使うため、privileged_modeをtrueにして、特権を付与
    privileged_mode = true
  }
}

resource "aws_codepipeline" "tech-blog" {
  name     = "tech-blog"
  role_arn = module.codepipeline_role.iam_role_arn


  # GitHub からソースコードを取得する
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = 1
      output_artifacts = ["Source"]

      configuration = {
        Owner  = "Kumaeers"
        Repo   = "tech-blog"
        Branch = "master"
        # CodePipelineの起動はWebhookから行うため、PollForSourceChangesをfalseにしてポーリングは無効
        PollForSourceChanges = false
      }
    }
  }

  # CodeBuildを実行し、ECRにDockerイメージをプッシュする
  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = 1
      input_artifacts  = ["Source"]
      output_artifacts = ["Build"]

      configuration = {
        ProjectName = aws_codebuild_project.tech-blog.id
      }
    }
  }

  # ECSへDockerイメージをデプロイする
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = 1
      input_artifacts = ["Build"]

      configuration = {
        ClusterName = aws_ecs_cluster.tech-blog.name
        ServiceName = aws_ecs_service.tech-blog.name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  artifact_store {
    location = aws_s3_bucket.artifact.id
    type     = "S3"
  }
}

resource "aws_codepipeline_webhook" "tech-blog" {
  name = "tech-blog"
  # Webhookを受け取ったら起動するパイプライン
  target_pipeline = aws_codepipeline.tech-blog.name
  # そのアクション
  target_action  = "Source"
  authentication = "GITHUB_HMAC"

  # これはtfstateに書かれるが,gitignoreしてる
  authentication_configuration {
    secret_token = "VeryRandomStringMoreThan20Byte!"
  }

  # 起動条件　pipelineでmasterブランチを選択してるためそこになる
  filter {
    json_path    = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

# githubのリソースを操作するためproviderを定義
provider "github" {
  organization = "Kumaeers"
}

# pipelineでキャッチするwebhook
resource "github_repository_webhook" "tech-blog" {
  repository = "tech-blog"

  # 通知先の設定
  configuration {
    url = aws_codepipeline_webhook.tech-blog.url
    # pipeline側のsecret_tokenと同じ値
    secret       = "VeryRandomStringMoreThan20Byte!"
    content_type = "json"
    insecure_ssl = false
  }

  events = ["push"]
}
