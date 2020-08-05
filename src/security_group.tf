# セキュリティグループ　=> インスタンスごとに定義できるファイウォール
# ネットワークACL => サブネットごとに定義するファイアウォール
# セキュリティグループのモジュールを使って定義
# module "example_sg" {
#   source      = "./security_group"
#   name        = "module-sg"
#   vpc_id      = aws_vpc.example.id
#   port        = 80
#   cidr_blocks = ["0.0.0.0/0"]
# }

# # moduleでsgを定義
# module "http_sg" {
#   source      = "./security_group"
#   name        = "http-sg"
#   vpc_id      = aws_vpc.example.id
#   port        = 80
#   cidr_blocks = ["0.0.0.0/0"]
# }

# module "https_sg" {
#   source      = "./security_group"
#   name        = "https-sg"
#   vpc_id      = aws_vpc.example.id
#   port        = 443
#   cidr_blocks = ["0.0.0.0/0"]
# }

# module "http_redirect_sg" {
#   source = "./security_group"
#   name   = "http-redirect-sg"
#   vpc_id = aws_vpc.example.id
#   # redirectは8080
#   port        = 8080
#   cidr_blocks = ["0.0.0.0/0"]
# }


# module "nginx_sg" {
#   source      = "./security_group"
#   name        = "nginx-sg"
#   vpc_id      = aws_vpc.example.id
#   port        = 80
#   cidr_blocks = [aws_vpc.example.cidr_block]
# }

# module "redis_sg" {
#   source      = "./security_group"
#   name        = "redis-sg"
#   vpc_id      = aws_vpc.example.id
#   port        = 6379
#   cidr_blocks = [aws_vpc.example.cidr_block]
# }


# module "mysql_sg" {
#   source = "./security_group"
#   name   = "mysql-sg"
#   vpc_id = aws_vpc.example.id
#   port   = 3306
#   # vpc内のみ通信許可
#   cidr_blocks = [aws_vpc.example.cidr_block]
# }
