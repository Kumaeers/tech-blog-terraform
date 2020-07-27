# IAM ロールでは、自身をなんのサービスに関連付けるか宣言する = 信頼ポリシー 誰がそれをできるか定義
# data "aws_iam_policy_document" "ec2_assume_role" {
#   statement {
#     actions = ["sts:AssumeRole"]

#     principals {
#       type        = "Service"
#       # このIAMロールはEC2にのみ関連付けできる
#       identifiers = ["ec2.amazonaws.com"]
#     }
#   }
# }

# # exampleはdescribeのポリシーという設定　ポリシードキュメントを保持するリソース
# resource "aws_iam_policy" "example" {
#   name   = "example"
#   policy = data.aws_iam_policy_document.allow_describe_regions.json
# }

# # ロール名と信頼ポリシーを指定
# resource "aws_iam_role" "example" {
#   name               = "example"
#   assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
# }
 
# # IAM ロールにIAM ポリシーをアタッチする　
# # IAM ロールとIAM ポリシーは、関連付けないと機能しない 
# resource "aws_iam_role_policy_attachment" "example" {
#   role       = aws_iam_role.example.name
#   policy_arn = aws_iam_policy.example.arn
# }

# # 何ができるのかを定義
# # ・Effect：Allow（許可）またはDeny（拒否）
# # ・Action： なんのサービスで、どんな操作が実行できるか
# # ・Resource： 操作可能なリソースはなにか
# data "aws_iam_policy_document" "allow_describe_regions" {
#   statement {
#     effect    = "Allow"
#     actions   = ["ec2:DescribeRegions"] # リージョン一覧を取得する
#     resources = ["*"]
#   }
# }

# module "describe_regions_for_ec2" {
#   source     = "./iam_role"
#   name       = "describe_regions_for_ec2"
#   identifier = "ec2.amazonaws.com"
#   policy     = data.aws_iam_policy_document.allow_describe_regions.json
# }

provider "aws" {
  profile = "default"
  region  = "ap-northeast-1"
}

# プライベートのバケット
resource "aws_s3_bucket" "private" {
  bucket = "private-kumaeers-terraform"

  # オブジェクトを変更・削除しても、いつでも以前のバージョンへ復元できるのがversioning
  versioning {
    enabled = true
  }

  # 暗号化を有効にすると、オブジェクト保存時に自動で暗号化しオブジェクト参照時に自動で復号する 使い勝手が悪くなることもなく、デメリットがほぼない
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# プライベートバケットのパブリックアクセスを全てブロック
resource "aws_s3_bucket_public_access_block" "private" {
  bucket = aws_s3_bucket.private.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# パブリックバケット
resource "aws_s3_bucket" "public" {
  bucket = "public-kumaeers-terraform"
  # aclはアクセス権の設定　デフォルトではprivateでAWSアカウント以外ではアクセスできないため、public-readでインターネットからの読み込みを許可
  acl = "public-read"

  cors_rule {
    allowed_origins = ["https://example.com"]
    allowed_methods = ["GET"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

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

# S3へのアクセス権をバケットポリシーで設定
resource "aws_s3_bucket_policy" "alb_log" {
  bucket = aws_s3_bucket.alb_log.id
  policy = data.aws_iam_policy_document.alb_log.json
}

# AWSが管理しているアカウントでALBから書き込みをする
data "aws_iam_policy_document" "alb_log" {
  statement {
    effect = "Allow"
    actions = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.alb_log.id}/*"]

    principals {
      type        = "AWS"
      identifiers = ["582318560864"]
    }
  }
}

# vpc
resource "aws_vpc" "example" {
  # 10.0までがvpcになる
  cidr_block            = "10.0.0.0/16"
  # AWSのDNSサーバーによる名前解決を有効にする
  enable_dns_support    = true
  # あわせて、VPC 内のリソースにパブリックDNSホスト名を自動的に割り当てるため、enable_dns_hostnamesをtrueに
  enable_dns_hostnames = true

  # Nameタグでこのvpcを識別できるようにする
  tags = {
    Name = "example"
  }
}

# vpcのサブネット
resource "aws_subnet" "public_0" {
  vpc_id                  = aws_vpc.example.id
  # 特にこだわりがなければ、VPC では「/16」単位、サブネットでは「/24」単位にすると分かりやすい 
  # 10.0.0までがサブネット
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  # そのサブネットで起動したインスタンスにパブリックIPアドレスを自動的に割り当てる
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
}

# vpcとインターネットの接続のため
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

# インターネットゲートウェイからネットワークにデータを流すため、ルーティング情報を管理するルートテーブルが必要
# ローカルルートが自動作成されvpc内で通信できるようになる　これはterraformでも管理はできない
# ルートのテーブル
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
}

# ルートはルートテーブルの1レコード
# destination_cidr_blockで出口はインターネットなので、そのどこにもいけるということ
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.example.id
  destination_cidr_block = "0.0.0.0/0"
}

# どのサブネットにルートテーブルを当てるのか定義
resource "aws_route_table_association" "public_0" {
  subnet_id      = aws_subnet.public_0.id
  route_table_id = aws_route_table.public.id
}

# どのサブネットにルートテーブルを当てるのか定義
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.65.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.66.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
}

# マルチAZのためテーブルを２つ用意
resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.example.id
}

# privateのルートテーブルにNATのルートを追加
resource "aws_route" "private_0" {
  route_table_id         = aws_route_table.private_0.id
  # privateからのネットへの接続のため、nat_gate_way
  nat_gateway_id         = aws_nat_gateway.nat_gateway_0.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_1.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_0" {
  subnet_id      = aws_subnet.private_0.id
  route_table_id = aws_route_table.private_0.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}

# NATゲートウェイにelastic ipを割り当てる
# NATにはpublic_ipが必要になるため
resource "aws_eip" "nat_gateway_0" {
  vpc          = true
  # 実はpublicにいるinternet_gatewayに依存している
  depends_on   = [aws_internet_gateway.example] 
}

resource "aws_eip" "nat_gateway_1" {
  vpc          = true
  depends_on   = [aws_internet_gateway.example] 
}

# NATの定義
resource "aws_nat_gateway" "nat_gateway_0" {
  # eipをNATに割り当て
  allocation_id = aws_eip.nat_gateway_0.id
  # NATはプライベートじゃなくpublicサブネットに置く
  subnet_id     = aws_subnet.public_0.id
  # 実はpublicにいるinternet_gatewayに依存している
  depends_on    = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_gateway_1.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.example]
}

# セキュリティグループ　=> インスタンスごとに定義できるファイウォール
# ネットワークACL => サブネットごとに定義するファイアウォール
# セキュリティグループのモジュールを使って定義
module "example_sg" {
  source      = "./security_group"
  name        = "module-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

# ALB
resource "aws_lb" "example" {
  name                        = "example"
  load_balancer_type          = "application"
  # vpc向けのalbの場合はinternalはtrue
  internal                    = false
  # タイムアウトのデフォルト値は60
  idle_timeout                = 60
  # 削除保護　本番で誤って消さないように
  # enable_deletion_protection  = true
  enable_deletion_protection  = false

  # albが属するsubnetを指定　複数指定してクロスゾーンの負荷分散にする
  subnets = [
    aws_subnet.public_0.id,
    aws_subnet.public_1.id,
  ]

  # s3にログを吐きだす
  access_logs {
    bucket  = aws_s3_bucket.alb_log.id
    enabled = true
  }

  security_groups = [
    module.http_sg.security_group_id,
    module.https_sg.security_group_id,
    module.http_redirect_sg.security_group_id,
  ]
}

output "alb_dns_name" {
  value = aws_lb.example.dns_name
}

# moduleでsgを定義
module "http_sg" {
  source      = "./security_group"
  name        = "http-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

module "https_sg" {
  source      = "./security_group"
  name        = "https-sg"
  vpc_id      = aws_vpc.example.id
  port        = 443
  cidr_blocks = ["0.0.0.0/0"]
}

module "http_redirect_sg" {
  source      = "./security_group"
  name        = "http-redirect-sg"
  vpc_id      = aws_vpc.example.id
  # redirectは8080
  port        = 8080
  cidr_blocks = ["0.0.0.0/0"]
}

# リスナーでALBがどのポートのリクエストを受け付けるか定義
# リスナーは複数ALBにアタッチできる
resource "aws_lb_listener" "http" {
  # listenerのルールは複数設定でき、異なるアクションを実行できる
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"

  # どのルールにも合致しなければdefaultが実行される
  # ・forward： リクエストを別のターゲットグループに転送
  # ・fixed-response： 固定のHTTP レスポンスを応答
  # ・redirect： 別のURL にリダイレクト
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは[HTTP]です"
      status_code  = "200"
    }
  }
}

# ホストゾーンはDNSレコードを束ねるリソース　Route 53 でドメインを登録した場合は、自動的に作成されます。同時に4つのNSレコード（ネームサーバー）とSOAレコード(Start of Authority DNSの問い合わせを行ってくれる入り口のドメイン)も作成される
# ドメインはterraformでは作成できないのでコンソールで登録する
data "aws_route53_zone" "example" {
  name = "kumaeers.example.com"
}

# resource "aws_route53_zone" "test_example" {
#   name = "test.example.com"
# }

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.example.zone_id
  name    = data.aws_route53_zone.example.name
  # CNAMEレコードは「ドメイン名→CNAME レコードのドメイン名→IP アドレス」という流れで名前解決を行う
  # 一方、ALIAS レコードは「ドメイン名→IPアドレス」という流れで名前解決が行われ、パフォーマンスが向上する
  # 今回はAレコード
  type    = "A"

  alias {
    name                   = aws_lb.example.dns_name
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}

output "domain_name" {
  value = aws_route53_record.example.name
}

resource "aws_acm_certificate" "example" {
  domain_name               = aws_route53_record.example.name
  # ドメイン名を追加したければ[]この中に指定する
  subject_alternative_names = []
  # 自動更新したい場合はドメインの所有権の検証方法をDNS検証にする
  validation_method         = "DNS"

  # ライフサイクルはTerraform独自の機能で、すべてのリソースに設定可能
  # リソースを作成してから、リソースを削除する」という逆の挙動に変更
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "example_certificate" {
  name    = aws_acm_certificate.example.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.example.domain_validation_options[0].resource_record_type
  records = [aws_acm_certificate.example.domain_validation_options[0].resource_record_value]
  zone_id = data.aws_route53_zone.example.id
  ttl     = 60
}

# SSL 証明書の検証完了まで待機
resource "aws_acm_certificate_validation" "example" {
  certificate_arn         = aws_acm_certificate.example.arn
  validation_record_fqdns = [aws_route53_record.example_certificate.fqdn]
}

# httpsのリスナー追加
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  # 作成したSSL証明書を設定
  certificate_arn   = aws_acm_certificate.example.arn
  # AWSで推奨されているセキュリティポリシーを設定
  ssl               = "ELBSecurityPolicy-2016-08"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは[HTTPS]です"
      status_code  = "200"
    }
  }
}

# HTTPをHTTPSへリダイレクトするリスナー
resource "aws_lb_listener" "redirect_http_to_https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    fixed_response {
      port         = "443"
      protocol     = "HTTPS"
      status_code  = "HTTP_301"
    }
  }
}

# ターゲットグループ = ALBがリクエストをフォワードする対象
resource "aws_lb_target_group" "example" {
  name                  = "example"
  # EC2インスタンスやIPアドレス、Lambda関数などが指定できる Fargateはipを指定する
  target_type           = "ip"
  # ipを指定した場合はさらに、vpc_id・port・protocolを設定
  vpc_id                = aws_vpc.example.id
  port                  = 80
  # ALBからはHTTPプロトコルで接続を行う
  protocol              = "HTTP"
  # ターゲットの登録を解除する前に、ALBが待機する時間
  deregistration_delay  = 300

  health_check {
    # ヘルスチェックで使用するパス
    path                = "/"
    # 正常判定を行うまでのヘルスチェック実行回数
    healthy_threshold   = 5
    # 異常判定を行うまでのヘルスチェック実行回数
    unhealthy_threshold = 2
    # ヘルスチェックのタイムアウト時間（秒）
    timeout             = 5
    # ヘルスチェックの実行間隔（秒）
    interval            = 30
    # 正常判定を行うために使用するHTTP ステータスコード
    matcher             = 200
    # ヘルスチェックで使用するポート traffic-portでは上で記述した80が使われる
    port                = "traffic-port"
    # ヘルスチェック時に使用するプロトコル
    protocol            = "HTTP"
  }

  # アプリケーションロードバランサーとターゲットグループを、ECSと同時に作成するとエラーになるため依存関係を制御する
  depends_on = [aws_lb.example]
}

# ターゲットグループへのリスナールール
resource "aws_lb_listener" "example" {
  listener_arn = aws_lb_listener.https.arn
  # 数字が小さいほど、優先順位が高い なお、デフォルトルールはもっとも優先順位が低い
  priority = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }

  # conditionには、「/img/*」のようなパスベースや「example.com」のようなホストベースなどで、条件を指定でき「/*」はすべてのパスでマッチする
  condition {
    field = "path-pattern"
    value = ["/*"]
  }
}
