# DB用のSSMパラメータストア設定
# resource "aws_ssm_parameter" "db_username" {
#   name        = "/db/username"
#   value       = "root"
#   type        = "String"
#   description = "データベースのユーザー名"
# }

# このままだと暗号化すべきパスワードがバージョン管理されてしまう
# Terraform ではダミー値を設定して、あとでAWS CLI から更新するという戦略を取る
# 好みの問題だがSSMパラメータはTerraform管理しなくても良いが、
# 外部サービスのクレデンシャルの発行方法など、ロストしやすい情報をコメントとして残す場所として使うには最適
# resource "aws_ssm_parameter" "db_password" {
#   name        = "/db/password"
#   value       = "uninitialized"
#   type        = "SecureString"
#   description = "データベースのパスワード"

#   lifecycle {
#     ignore_changes = [value]
#   }
# }

# GOコンテナから接続するためのDB用のSSMパラメータストア設定
resource "aws_ssm_parameter" "db_dsn" {
  name        = "/db/dsn"
  value       = "uninitialized"
  type        = "SecureString"
  description = "データベースのDSN"

  lifecycle {
    ignore_changes = [value]
  }
}

# Firebaseの秘密鍵
resource "aws_ssm_parameter" "firebase_secrets" {
  name        = "/firebase/secrets"
  value       = "uninitialized"
  type        = "SecureString"
  description = "firebaseの秘密鍵"

  lifecycle {
    ignore_changes = [value]
  }
}
