# ライフサイクルルールのあるバケット（有効期限つきバケット)
resource "aws_s3_bucket" "alb_log" {
  bucket = "alb-log-kumaeers-terraform"

  # バージョニングでS3の中身が複数残ってるのを強制的に消す
  force_destroy = true

  lifecycle_rule {
    enabled = true

    expiration {
      days = "180"
    }
  }
}

# CodePipeline の各ステージで、データの受け渡しに使用するアーティファクトストア用のS3バケット
resource "aws_s3_bucket" "artifact" {
  bucket = "artifact-kumaeers-terraform"

  force_destroy = true

  lifecycle_rule {
    enabled = true

    expiration {
      days = "180"
    }
  }
}

resource "aws_s3_bucket" "operation" {
  bucket = "operation-tech-blog"

  force_destroy = true

  lifecycle_rule {
    enabled = true

    expiration {
      days = "180"
    }
  }
}
