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
