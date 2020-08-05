# # ElastiCacheのRedisエンジン => Memcachedと違いデータの永続化とレプリケーションとレプリケーションによるクラスタリングが可能
# # ElastiCacheパラメータグループがRedisの設定
# resource "aws_elasticache_parameter_group" "example" {
#   name   = "example"
#   family = "redis5.0"

#   # クラスタリングで可用性を高くしないことでコストを下げる
#   parameter {
#     name  = "cluster-enabled"
#     value = "no"
#   }
# }

# # ElastiCache サブネット
# resource "aws_elasticache_subnet_group" "example" {
#   name       = "example"
#   subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id]
# }

# # ElastiCacheレプリケーショングループ
# resource "aws_elasticache_replication_group" "example" {
#   # Redisのエンドポイントで使う識別子
#   replication_group_id          = "example"
#   replication_group_description = "Cluster Disabled"
#   # memcachedかredis
#   engine         = "redis"
#   engine_version = "5.0.4"
#   # ノード数 プライマリー 1 + レプリカ 2 = 3
#   number_cache_clusters = 3
#   # 低スペックだとapplyに時間がすごくかかるらしい
#   node_type = "cache.m3.medium"
#   # スナップショットのタイミング
#   snapshot_window = "09:10-10:10"
#   # スナップショット保存期間
#   snapshot_retention_limit = 7
#   maintenance_window       = "mon:10:40-mon:11:40"
#   # サブネットをマルチAZ化してるため自動フェイルオーバーが有効にできる
#   automatic_failover_enabled = true
#   port                       = 6379
#   apply_immediately          = false
#   # vpc内のみ許可
#   security_group_ids   = [module.redis_sg.security_group_id]
#   parameter_group_name = aws_elasticache_parameter_group.example.name
#   subnet_group_name    = aws_elasticache_subnet_group.example.name
# }


