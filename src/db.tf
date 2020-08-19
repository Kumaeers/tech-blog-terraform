# RDSの暗号化のためのマスターキー
resource "aws_kms_key" "tech-blog" {
  description = "For tech-blog's RDS Customer Master Key"
  enable_key_rotation = true
  is_enabled = true
  deletion_window_in_days = 30
}

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

# my.cnfファイルに定義するようなデータベースの設定は、DBパラメータグループで記述する
resource "aws_db_parameter_group" "tech-blog" {
  name   = "tech-blog"
  family = "mysql5.7"

  parameter {
    name  = "character_set_database"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
}

# オプションでMariaDB監査プラグインを追加　
resource "aws_db_option_group" "tech-blog" {
  name                 = "tech-blog"
  engine_name          = "mysql"
  major_engine_version = "5.7"

  # ユーザーのログオンや実行したクエリなどの、アクティビティを記録するためのプラグイン
  option {
    option_name = "MARIADB_AUDIT_PLUGIN"
  }
}

# DBを起動するサブネットの定義
resource "aws_db_subnet_group" "tech-blog" {
  name = "tech-blog"
  # 異なるサブネットを含めマルチAZ化
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id]
}

# DB
resource "aws_db_instance" "tech-blog" {
  # データベースのエンドポイントで使う識別子
  identifier        = "tech-blog"
  engine            = "mysql"
  engine_version    = "5.7.25"
  instance_class    = "db.t3.small"
  allocated_storage = 20
  # スケールアウト用
  max_allocated_storage = 100
  # 「汎用SSD」か「プロビジョンドIOPS」を設定 「gp2」は汎用SSD
  storage_type      = "gp2"
  storage_encrypted = true
  # ディスク暗号化
  kms_key_id = aws_kms_key.tech-blog.arn
  username   = "admin"
  password   = "VeryStrongPassword!"
  # aws_db_subnet_groupでmulti_azしてるため可能
  multi_az = true
  # VPC 外からのアクセスを遮断
  publicly_accessible = false
  # バックアップのタイミング
  backup_window = "09:10-09:40"
  # バックアップ期間　最大35日
  backup_retention_period = 30
  # メンテナンスのタイミング メンテナンス自体は無効化することはできない
  maintenance_window         = "mon:10:10-mon:10:40"
  auto_minor_version_upgrade = false
  # 削除保護 本番稼働したらtrueにする
  # deletion_protection = true
  deletion_protection = false
  # インスタンス削除時のスナップショット作成
  skip_final_snapshot = false
  port                = 3306
  # RDSでは一部の設定変更に再起動が伴うので即時反映を避ける
  apply_immediately = false
  # VPC 内からの通信のみ許可
  vpc_security_group_ids = [module.mysql_sg.security_group_id]
  parameter_group_name   = aws_db_parameter_group.tech-blog.name
  option_group_name      = aws_db_option_group.tech-blog.name
  db_subnet_group_name   = aws_db_subnet_group.tech-blog.name

  # ignore_changesで「password」を指定してapplyすることで、変更をtfstateに書かれるのを回避
  # 初期は平文で入力しのちに下のコマンドで変更する
  # aws rds modify-db-instance --db-instance-identifier 'tech-blog' \ --master-user-password 'NewMasterPassword!'
  lifecycle {
    ignore_changes = [password]
  }
}

