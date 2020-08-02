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
  bucket                  = aws_s3_bucket.private.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
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
    effect    = "Allow"
    actions   = ["s3:PutObject"]
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
  cidr_block = "10.0.0.0/16"
  # AWSのDNSサーバーによる名前解決を有効にする
  enable_dns_support = true
  # あわせて、VPC 内のリソースにパブリックDNSホスト名を自動的に割り当てるため、enable_dns_hostnamesをtrueに
  enable_dns_hostnames = true

  # Nameタグでこのvpcを識別できるようにする
  tags = {
    Name = "example"
  }
}

# vpcのサブネット
resource "aws_subnet" "public_0" {
  vpc_id = aws_vpc.example.id
  # 特にこだわりがなければ、VPC では「/16」単位、サブネットでは「/24」単位にすると分かりやすい 
  # 10.0.0までがサブネット
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"
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
  route_table_id = aws_route_table.private_0.id
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
  vpc = true
  # 実はpublicにいるinternet_gatewayに依存している
  depends_on = [aws_internet_gateway.example]
}

resource "aws_eip" "nat_gateway_1" {
  vpc        = true
  depends_on = [aws_internet_gateway.example]
}

# NATの定義
resource "aws_nat_gateway" "nat_gateway_0" {
  # eipをNATに割り当て
  allocation_id = aws_eip.nat_gateway_0.id
  # NATはプライベートじゃなくpublicサブネットに置く
  subnet_id = aws_subnet.public_0.id
  # 実はpublicにいるinternet_gatewayに依存している
  depends_on = [aws_internet_gateway.example]
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
  name               = "example"
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
  source = "./security_group"
  name   = "http-redirect-sg"
  vpc_id = aws_vpc.example.id
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
  type = "A"

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
  domain_name = aws_route53_record.example.name
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
  certificate_arn = aws_acm_certificate.example.arn
  # AWSで推奨されているセキュリティポリシーを設定
  ssl = "ELBSecurityPolicy-2016-08"

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
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ターゲットグループ = ALBがリクエストをフォワードする対象
resource "aws_lb_target_group" "example" {
  name = "example"
  # EC2インスタンスやIPアドレス、Lambda関数などが指定できる Fargateはipを指定する
  target_type = "ip"
  # ipを指定した場合はさらに、vpc_id・port・protocolを設定
  vpc_id = aws_vpc.example.id
  port   = 80
  # ALBからはHTTPプロトコルで接続を行う
  protocol = "HTTP"
  # ターゲットの登録を解除する前に、ALBが待機する時間
  deregistration_delay = 300

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

# ECSクラスタは、Docker コンテナを実行するホストサーバーを、論理的に束ねるリソース
resource "aws_ecs_cluster" "example" {
  name = "example"
}

# コンテナの実行単位 は「タスク」で「タスク定義」から生成される　
# クラスがタスク定義、タスクがインスタンスという関係
# たとえば、Railsアプリケーションの前段にnginxを配置する場合、ひとつのタスクの中でRails コンテナとnginxコンテナが実行される
resource "aws_ecs_task_definition" "example" {
  # タスク定義名のプレフィックスのこと example:1のようになる
  family = "example"
  # cpuに256を指定する場合、memoryで指定できる値は512・1024・2048のいずれか
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "aws_vpc"
  requires_compatibilities = ["FARGATE"]
  # 実際にタスクで実行するコンテナの定義
  container_definitions = file("./container_definitions.json")

  execution_role_arn = module.ecs_task_execution_role.iam_role_arn
}

# ECSサービスは起動するタスクの数を定義でき、指定した数のタスクを維持　なんらかの理由でタスクが終了してしまった場合、自動的に新しいタスクを起動してくれる
# またECSサービスはALBとの橋渡し役にもなり、インターネットからのリクエストはALBで受けそのリクエストをコンテナにフォワードさせる
resource "aws_ecs_service" "example" {
  name            = "example"
  cluster         = aws_ecs_cluster.example.arn
  task_definition = aws_ecs_task_definition.example.arn
  # 2個以上コンテナ起動する
  desired_count = 2
  launch_type   = "FARGATE"
  # latestが最新ではないので明示的にする必要あり
  platform_version = "1.3.0"
  # タスク起動時のヘルスチェック猶予期間 0だとタスクの起動と終了が無限に続く可能性あり
  health_check_grace_period_seconds = 60

  # サブネットとセキュリティグループを設定
  network_configuration {
    assign_public_ip = false
    security_groups  = [module.nginx_sg.security_group_id]

    subnets = [
      aws_subnet.private_0.id,
      aws_subnet.private_1.id,
    ]
  }

  # load_balancerでターゲットグループとコンテナの名前・ポート番号を指定し、上記のロードバランサーと関連付け
  load_balancer {
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "example"
    container_port   = 80
  }

  # 　Fargate の場合、デプロイのたびにタスク定義が更新され、plan時に差分が出るのを無視する
  lifecycle {
    ignore_changes = [task_definition]
  }
}

module "nginx_sg" {
  source      = "./security_group"
  name        = "nginx-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = [aws_vpc.example.cidr_block]
}

# CloudWatchLogsでECSのログを取る
resource "aws_cloudwatch_log_group" "for_ecs" {
  name = "/ecs/example"
  # ログの保持期間
  retention_in_days = 180
}

# 公式のECSの実行ロールを参照
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECSのポリシードキュメント
data "aws_iam_policy_document" "ecs_task_execution" {
  # 上で参照しているのを継承する
  source_json = data.aws_iam_policy.ecs_task_execution_role_policy.policy

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
  }
}

# iam_roleモジュールで上記のポリシーを持ったロールを作成
module "ecs_task_execution_role" {
  source     = "./iam_role"
  name       = "ecs-task-execution"
  identifier = "ecs-tasks.amazonaws.com"
  policy     = data.aws_iam_policy_document.ecs_task_execution.json
}

# # バッチ用CloudWatch Logs
# resource "aws_cloudwatch_log_group" "for_ecs_scheduled_tasks" {
#   name              = "/ecs-scheduled-tasks/example"
#   retention_in_days = 180
# }

# # バッチ用のタスク定義
# resource "aws_ecs_task_definition" "example_batch" {
#   family                   = "example-batch"
#   cpu                      = "256"
#   memory                   = "512"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   container_definitions    = file("./batch_container_definitions.json")
#   execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
# }

# # バッチ実行用のロール
# module "ecs_events_role" {
#   source     = "./iam_role"
#   name       = "ecs-events"
#   identifier = "events.amazonaws.com"
#   policy     = data.aws_iam_policy.ecs_events_role_policy.policy
# }

# # ポリシー
# data "aws_iam_policy" "ecs_events_role_policy" {
#   arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
# }

# # CloudWatchイベントルールを設定する
# resource "aws_cloudwatch_event_rule" "example_batch" {
#   name                = "example-batch"
#   description         = "とても重要なバッチです"
#   # cron式： 「cron(0 8 * * ? *)」のように記述します。東京リージョンの場合でも、タイムゾーンはUTCになります。また、設定の最小精度は1 分です。
#   # rate式： 「rate(5 minutes)」のように記述します。単位は『1 の場合は単数形、それ以外は複数形』で書きます。つまり、「rate(1 hours)」や「rate(5 hour)」のように書くことはできないので注意しましょう。
#   # 2分ごとにバッチ処理する
#   schedule_expression = "cron(*/2 * * * ? *)"
# }

# # CloudWatch イベントターゲットで実行するジョブを指定する
# resource "aws_cloudwatch_event_target" "example_batch" {
#   target_id = "example-batch"
#   # 上で定義したルールのもと動く
#   rule      = aws_cloudwatch_event_rule.example_batch.name
#   role_arn  = module.ecs_events_role.iam_role_arn
#   # ECSの場合はクラスターを指定する
#   arn       = aws_ecs_cluster.example.arn

#   # ECSサービスとほぼ同じ
#   ecs_target {
#     launch_type         = "FARGATE"
#     task_count          = 1
#     platform_version    = "1.3.0"
#     task_definition_arn = aws_ecs_task_definition.example_batch.arn

#     network_configuration {
#       assign_public_ip = "false"
#       subnets          = [aws_subnet.private_0.id]
#     }
#   }
# }

# DB用のSSMパラメータストア設定
resource "aws_ssm_parameter" "db_username" {
  name        = "/db/username"
  value       = "root"
  type        = "String"
  description = "データベースのユーザー名"
}

# このままだと暗号化すべきパスワードがバージョン管理されてしまう
# Terraform ではダミー値を設定して、あとでAWS CLI から更新するという戦略を取る
# 好みの問題だがSSMパラメータはTerraform管理しなくても良いが、
# 外部サービスのクレデンシャルの発行方法など、ロストしやすい情報をコメントとして残す場所として使うには最適
resource "aws_ssm_parameter" "db_raw_password" {
  name        = "/db/password"
  value       = "uninitialized"
  type        = "SecureString"
  description = "データベースのパスワード"

  lifecycle {
    ignore_changes = [value]
  }
}

# my.cnfファイルに定義するようなデータベースの設定は、DBパラメータグループで記述する
resource "aws_db_parameter_group" "example" {
  name   = "example"
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
resource "aws_db_option_group" "example" {
  name                 = "example"
  engine_name          = "mysql"
  major_engine_version = "5.7"

  # ユーザーのログオンや実行したクエリなどの、アクティビティを記録するためのプラグイン
  option {
    option_name = "MARIADB_AUDIT_PLUGIN"
  }
}

# DBを起動するサブネットの定義
resource "aws_db_subnet_group" "example" {
  name = "example"
  # 異なるサブネットを含めマルチAZ化
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id]
}

# DB
resource "aws_db_instance" "example" {
  # データベースのエンドポイントで使う識別子
  identifier        = "example"
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
  kms_key_id = aws_kms_key.example.arn
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
  # 削除保護
  deletion_protection = true
  # インスタンス削除時のスナップショット作成
  skip_final_snapshot = false
  port                = 3306
  # RDSでは一部の設定変更に再起動が伴うので即時反映を避ける
  apply_immediately = false
  # VPC 内からの通信のみ許可
  vpc_security_group_ids = [module.mysql_sg.security_group_id]
  parameter_group_name   = aws_db_parameter_group.example.name
  option_group_name      = aws_db_option_group.example.name
  db_subnet_group_name   = aws_db_subnet_group.example.name

  # ignore_changesで「password」を指定してapplyすることで、変更をtfstateに書かれるのを回避
  # 初期は平文で入力しのちに下のコマンドで変更する
  # aws rds modify-db-instance --db-instance-identifier 'example' \ --master-user-password 'NewMasterPassword!'
  lifecycle {
    ignore_changes = [password]
  }
}

module "mysql_sg" {
  source = "./security_group"
  name   = "mysql-sg"
  vpc_id = aws_vpc.example.id
  port   = 3306
  # vpc内のみ通信許可
  cidr_blocks = [aws_vpc.example.cidr_block]
}

# ElastiCacheのRedisエンジン => Memcachedと違いデータの永続化とレプリケーションとレプリケーションによるクラスタリングが可能
# ElastiCacheパラメータグループがRedisの設定
resource "aws_elasticache_parameter_group" "example" {
  name   = "example"
  family = "redis5.0"

  # クラスタリングで可用性を高くしないことでコストを下げる
  parameter {
    name  = "cluster-enabled"
    value = "no"
  }
}

# ElastiCache サブネット
resource "aws_elasticache_subnet_group" "example" {
  name       = "example"
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id]
}

# ElastiCacheレプリケーショングループ
resource "aws_elasticache_replication_group" "example" {
  # Redisのエンドポイントで使う識別子
  replication_group_id          = "example"
  replication_group_description = "Cluster Disabled"
  # memcachedかredis
  engine         = "redis"
  engine_version = "5.0.4"
  # ノード数 プライマリー 1 + レプリカ 2 = 3
  number_cache_clusters = 3
  # 低スペックだとapplyに時間がすごくかかるらしい
  node_type = "cache.m3.medium"
  # スナップショットのタイミング
  snapshot_window = "09:10-10:10"
  # スナップショット保存期間
  snapshot_retention_limit = 7
  maintenance_window       = "mon:10:40-mon:11:40"
  # サブネットをマルチAZ化してるため自動フェイルオーバーが有効にできる
  automatic_failover_enabled = true
  port                       = 6379
  apply_immediately          = false
  # vpc内のみ許可
  security_group_ids   = [module.redis_sg.security_group_id]
  parameter_group_name = aws_elasticache_parameter_group.example.name
  subnet_group_name    = aws_elasticache_subnet_group.example.name
}

module "redis_sg" {
  source      = "./security_group"
  name        = "redis-sg"
  vpc_id      = aws_vpc.example.id
  port        = 6379
  cidr_blocks = [aws_vpc.example.cidr_block]
}

# ECR
resource "aws_ecr_repository" "example" {
  name = "example"
}

# ライフサイクルポリシーでイメージの数が増えすぎないように制御
resource "aws_ecr_lifecycle_policy" "example" {
  repository = aws_ecr_repository.example.name

  policy = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "Keep last 30 release tagged images",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["release"],
          "countType": "imageCountMoreThan",
          "countNumber": 30
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
  EOF
}

# build用のポリシー
data "aws_iam_policy_document" "codebuild" {
  statement {
    effect = "Allow"
    resources = ["*"]

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
  }
}

# build用のロール
module "codebuild_role" {
  source = "./iam_role"
  name = "codebuild"
  identifier = "codebuild.amazonaws.com"
  policy = data.aws_iam_policy_document.codebuild.json
}

# CodeBuildプロジェクト
resource "aws_codebuild_project" "example" {
  name = "example"
  service_role = module.codebuild_role.iam_role_arn

  # ビルド対象のソースをCodePipelineと連携する宣言
  source {
    type = "CODEPIPELINE"
  }

  # ビルド出力アーティファクトの格納先をCodePipelineと連携する宣言
  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image = "aws/codebuild/standard:2.0"
    # ビルド時にdocker コマンドを使うため、privileged_modeをtrueにして、特権を付与
    privileged_mode = true
  }
}

# CodePipeline用のポリシー
data "aws_iam_policy_document" "codepipeline" {
  statement {
    effect = "Allow"
    resources = ["*"]

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "iam:PassRole",
    ]
  }
}

# CodePipelineのロール
module "codepipeline_role" {
  source = "./iam_role"
  name = "codepipeline"
  identifier = "codepipeline.amazonaws.com"
  policy = data.aws_iam_policy_document.codepipeline.json
}

# CodePipeline の各ステージで、データの受け渡しに使用するアーティファクトストア用のS3バケット
resource "aws_s3_bucket" "artifact" {
  bucket = "artifact-pragmatic-terraform"

  lifecycle_rule {
    enabled = true

    expiration {
      days = "180"
    }
  }
}

resource "aws_codepipeline" "example" {
  name = "example"
  role_arn = module.codepipeline_role.iam_role_arn


  # GitHub からソースコードを取得する
  stage {
    name = "Source"

    action {
      name = "Source"
      category = "Source"
      owner = "ThirdParty"
      provider = "GitHub"
      version = 1
      output_artifacts = ["Source"]

      configuration = {
        Owner = "your-github-name"
        Repo = "your-repository"
        Branch = "master"
        # CodePipelineの起動はWebhookから行うため、PollForSourceChangesをfalseにしてポーリングは無効
        PollForSourceChange = false
      }
    }
  }

  # CodeBuildを実行し、ECRにDockerイメージをプッシュする
  stage {
    name = "Build"

    action {
      name = "Build"
      category = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      version = 1
      input_artifacts = ["Source"]
      output_artifacts = ["Build"]

      configuration = {
        ProjectName = aws_codebuild_project.example.id
      }
    }
  }

  # ECSへDockerイメージをデプロイする
  stage {
    name = "Deploy"

    action {
      name = "Deploy"
      category = "Deploy"
      owner = "AWS"
      provider = "ECS"
      version = 1
      input_artifacts = ["Build"]

      configuration = {
        ClusterName = aws_ecs_cluster.example.name
        ServiceName = aws_ecs_service.example.name
        FileName = "imagedefinitions.json"
      }
    }
  }

  artifact_store {
    location = aws_s3_bucket.artifact.id
    type = "S3"
  }
}

resource "aws_codepipeline_webhook" "example" {
  name = "example"
  # Webhookを受け取ったら起動するパイプライン
  target_pipeline = aws_codepipeline.example.name
  # そのアクション
  target_action = "Source"
  authentication = "GITHUB_HMAC"

  # これはtfstateに書かれるが,gitignoreしてる
  authentication_configuration {
    secret_token = "VeryRandomStringMoreThan20Byte!"
  }

  # 起動条件　pipelineでmasterブランチを選択してるためそこになる
  filter {
    json_path = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

# githubのリソースを操作するためproviderを定義
provider "github" {
  organization = "your-github-name"
}


# pipelineでキャッチするwebhook
resource "github_repository_webhook" "example" {
  repository = "your-repository"

  # 通知先の設定
  configuration {
    url = aws_codepipeline_webhook.example.url
    # pipeline側のsecret_tokenと同じ値
    secret = "VeryRandomStringMoreThan20Byte!"
    content_type = "json"
    insecure_ssl = false
  }

  events = ["push"]
}
