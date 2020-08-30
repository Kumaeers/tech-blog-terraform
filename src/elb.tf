# ALB
resource "aws_lb" "tech-blog" {
  name               = "tech-blog"
  load_balancer_type = "application"
  # vpc向けのalbの場合はinternalはtrue
  internal = false
  # タイムアウトのデフォルト値は60
  idle_timeout = 60
  # 削除保護　本番で誤って消さないように
  # enable_deletion_protection  = true
  enable_deletion_protection = false

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
    module.https_sg.security_group_id
  ]
}

output "alb_dns_name" {
  value = aws_lb.tech-blog.dns_name
}

variable "domain" {
  description = "Route 53 で管理しているドメイン名"
  type        = "string"

  default = "kumaeers-blog.com"
}

# ホストゾーンはDNSレコードを束ねるリソース　Route 53 でドメインを登録した場合は、自動的に作成されます。同時に4つのNSレコード（ネームサーバー）とSOAレコード(Start of Authority DNSの問い合わせを行ってくれる入り口のドメイン)も作成される
# ドメインはterraformでは作成できないのでコンソールで登録する
# ドメイン作成後Terraform で管理するため、resourceで登録する
# resource "aws_route53_zone" "tech-blog" {
#   name = var.domain
# }

data "aws_route53_zone" "tech-blog" {
  # name = var.domain
  zone_id = "Z019681625JWIOC1UGTL"
  vpc_id  = aws_vpc.tech-blog.id
}

resource "aws_route53_record" "tech-blog" {
  zone_id = data.aws_route53_zone.tech-blog.zone_id
  name    = data.aws_route53_zone.tech-blog.name
  # CNAMEレコードは「ドメイン名→CNAME レコードのドメイン名→IP アドレス」という流れで名前解決を行う
  # 一方、ALIAS レコードは「ドメイン名→IPアドレス」という流れで名前解決が行われ、パフォーマンスが向上する
  # 今回はAレコード
  type = "A"

  alias {
    name                   = aws_lb.tech-blog.dns_name
    zone_id                = aws_lb.tech-blog.zone_id
    evaluate_target_health = true
  }
}

output "domain_name" {
  value = aws_route53_record.tech-blog.name
}

resource "aws_acm_certificate" "tech-blog" {
  domain_name = aws_route53_record.tech-blog.name
  # ドメイン名を追加したければ[]この中に指定する
  subject_alternative_names = []
  # 自動更新したい場合はドメインの所有権の検証方法をDNS検証にする
  validation_method = "DNS"

  # ライフサイクルはTerraform独自の機能で、すべてのリソースに設定可能
  # リソースを作成してから、リソースを削除する」という逆の挙動に変更
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "tech-blog_certificate" {
  name    = aws_acm_certificate.tech-blog.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.tech-blog.domain_validation_options[0].resource_record_type
  records = [aws_acm_certificate.tech-blog.domain_validation_options[0].resource_record_value]
  zone_id = data.aws_route53_zone.tech-blog.id
  ttl     = 60
}

# SSL 証明書の検証完了まで待機
resource "aws_acm_certificate_validation" "tech-blog" {
  certificate_arn         = aws_acm_certificate.tech-blog.arn
  validation_record_fqdns = [aws_route53_record.tech-blog_certificate.fqdn]
}

# リスナーでALBがどのポートのリクエストを受け付けるか定義
# リスナーは複数ALBにアタッチできる
resource "aws_lb_listener" "http" {
  # listenerのルールは複数設定でき、異なるアクションを実行できる
  load_balancer_arn = aws_lb.tech-blog.arn
  port              = "80"
  protocol          = "HTTP"

  # どのルールにも合致しなければdefaultが実行される
  # ・forward： リクエストを別のターゲットグループに転送
  # ・fixed-response： 固定のHTTP レスポンスを応答
  # ・redirect： 別のURL にリダイレクト
  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# httpsのリスナー追加
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.tech-blog.arn
  port              = "443"
  protocol          = "HTTPS"
  # 作成したSSL証明書を設定
  certificate_arn = aws_acm_certificate.tech-blog.arn
  # AWSで推奨されているセキュリティポリシーを設定
  ssl_policy = "ELBSecurityPolicy-2016-08"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは[HTTPS]です"
      status_code  = "200"
    }
  }
}

# ターゲットグループ = ALBがリクエストをフォワードする対象
resource "aws_lb_target_group" "tech-blog" {
  name = "tech-blog"
  # EC2インスタンスやIPアドレス、Lambda関数などが指定できる Fargateはipを指定する
  target_type = "ip"
  # ipを指定した場合はさらに、vpc_id・port・protocolを設定
  vpc_id = aws_vpc.tech-blog.id
  port   = 80
  # ALBからはHTTPプロトコルで接続を行う
  protocol = "HTTP"
  # ターゲットの登録を解除する前に、ALBが待機する時間
  # deregistration_delay = 300
  deregistration_delay = 30

  health_check {
    # ヘルスチェックで使用するパス
    path = "/"
    # 正常判定を行うまでのヘルスチェック実行回数
    healthy_threshold = 5
    # 異常判定を行うまでのヘルスチェック実行回数
    unhealthy_threshold = 2
    # ヘルスチェックのタイムアウト時間（秒）
    timeout = 5
    # ヘルスチェックの実行間隔（秒）
    interval = 30
    # 正常判定を行うために使用するHTTP ステータスコード
    matcher = 200
    # ヘルスチェックで使用するポート traffic-portでは上で記述した80が使われる
    port = "traffic-port"
    # ヘルスチェック時に使用するプロトコル
    protocol = "HTTP"
  }

  # アプリケーションロードバランサーとターゲットグループを、ECSと同時に作成するとエラーになるため依存関係を制御する
  depends_on = [aws_lb.tech-blog]
}

# ターゲットグループへのリスナールール
resource "aws_lb_listener_rule" "tech-blog" {
  listener_arn = aws_lb_listener.https.arn
  # 数字が小さいほど、優先順位が高い なお、デフォルトルールはもっとも優先順位が低い
  priority = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tech-blog.arn
  }

  # conditionには、「/img/*」のようなパスベースや「example.com」のようなホストベースなどで、条件を指定でき「/*」はすべてのパスでマッチする
  condition {
    path_pattern {
      values = ["*"]
    }
  }
}
