# RDSの暗号化のためのマスターキー
resource "aws_kms_key" "tech-blog" {
  description = "For tech-blog's RDS Customer Master Key"
  enable_key_rotation = true
  is_enabled = true
  deletion_window_in_days = 30
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
  # ~~テスト用~~
  deletion_protection = false
  # インスタンス削除時のスナップショット作成しない
  skip_final_snapshot = true
  # ~~本番稼働したら~~
  # 削除保護
  # deletion_protection = true
  # インスタンス削除時のスナップショット作成する
  # skip_final_snapshot = false
  # スナップショットをとるなら必須
  # final_snapshot_identifier  = "example-finale-snapshot-id" 
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

