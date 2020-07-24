# IAM ロールでは、自身をなんのサービスに関連付けるか宣言する = 信頼ポリシー 誰がそれをできるか定義
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      # このIAMロールはEC2にのみ関連付けできる
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# exampleはdescribeのポリシーという設定　ポリシードキュメントを保持するリソース
resource "aws_iam_policy" "example" {
  name   = "example"
  policy = data.aws_iam_policy_document.allow_describe_regions.json
}

# ロール名と信頼ポリシーを指定
resource "aws_iam_role" "example" {
  name               = "example"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}
 
# IAM ロールにIAM ポリシーをアタッチする　
# IAM ロールとIAM ポリシーは、関連付けないと機能しない 
resource "aws_iam_role_policy_attachment" "example" {
  role       = aws_iam_role.example.name
  policy_arn = aws_iam_policy.example.arn
}

# 何ができるのかを定義
# ・Effect：Allow（許可）またはDeny（拒否）
# ・Action： なんのサービスで、どんな操作が実行できるか
# ・Resource： 操作可能なリソースはなにか
data "aws_iam_policy_document" "allow_describe_regions" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeRegions"] # リージョン一覧を取得する
    resources = ["*"]
  }
}

module "describe_regions_for_ec2" {
  source     = "./iam_role"
  name       = "describe_regions_for_ec2"
  identifier = "ec2.amazonaws.com"
  policy     = data.aws_iam_policy_document.allow_describe_regions.json
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
  example_dns_hostnames = true

  # Nameタグでこのvpcを識別できるようにする
  tags = {
    Name = "example"
  }
}

# vpcのサブネット
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.example.id
  # 特にこだわりがなければ、VPC では「/16」単位、サブネットでは「/24」単位にすると分かりやすい 
  # 10.0.0までがサブネット
  cidr_block              = "10.0.0.0/24"
  # そのサブネットで起動したインスタンスにパブリックIPアドレスを自動的に割り当てる
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
}

# vpcとインターネットの接続のため
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

# インターネットゲートウェイからネットワークにデータを流すため、ルーティング情報を管理するルートテーブルが必要
# ローカルルートが自動作成されvpc内で通信できるようになる　これはterraformでも管理はできない
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
}

# どのサブネットにルートテーブルを当てるのか定義
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

