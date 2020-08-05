# ライフサイクルルールのあるバケット（有効期限つきバケット)
resource "aws_s3_bucket" "alb_log" {
  bucket = "alb-log-kumaeers-terraform"

  lifecycle_rule {
    enabled = true

    expiration {
      days = "180"
    }
  }
}
