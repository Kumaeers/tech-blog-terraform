# セキュリティグループ　=> インスタンスごとに定義できるファイウォール
# ネットワークACL => サブネットごとに定義するファイアウォール
# セキュリティグループのモジュールを使って定義

# moduleでsgを定義
module "http_sg" {
  source      = "./module/security_group"
  name        = "http-sg"
  vpc_id      = aws_vpc.tech-blog.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

module "https_sg" {
  source      = "./module/security_group"
  name        = "https-sg"
  vpc_id      = aws_vpc.tech-blog.id
  port        = 443
  cidr_blocks = ["0.0.0.0/0"]
}

module "http_redirect_sg" {
  source = "./module/security_group"
  name   = "http-redirect-sg"
  vpc_id = aws_vpc.tech-blog.id
  # redirectは8080
  port        = 8080
  cidr_blocks = ["0.0.0.0/0"]
}

module "nginx_sg" {
  source      = "./module/security_group"
  name        = "nginx-sg"
  vpc_id      = aws_vpc.tech-blog.id
  port        = 80
  cidr_blocks = [aws_vpc.tech-blog.cidr_block]
}

# module "redis_sg" {
#   source      = "./module/security_group"
#   name        = "redis-sg"
#   vpc_id      = aws_vpc.tech-blog.id
#   port        = 6379
#   cidr_blocks = [aws_vpc.tech-blog.cidr_block]
# }


# module "mysql_sg" {
#   source = "./module/security_group"
#   name   = "mysql-sg"
#   vpc_id = aws_vpc.tech-blog.id
#   port   = 3306
#   # vpc内のみ通信許可
#   cidr_blocks = [aws_vpc.tech-blog.cidr_block]
# }
