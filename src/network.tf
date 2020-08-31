# vpc
resource "aws_vpc" "tech-blog" {
  # 10.0までがvpcになる
  cidr_block = "10.0.0.0/16"
  # AWSのDNSサーバーによる名前解決を有効にする
  enable_dns_support = true
  # あわせて、VPC 内のリソースにパブリックDNSホスト名を自動的に割り当てるため、enable_dns_hostnamesをtrueに
  enable_dns_hostnames = true

  # Nameタグでこのvpcを識別できるようにする
  tags = {
    Name = "tech-blog"
  }
}

# vpcのサブネット
resource "aws_subnet" "public_0" {
  vpc_id = aws_vpc.tech-blog.id
  # 特にこだわりがなければ、VPC では「/16」単位、サブネットでは「/24」単位にすると分かりやすい 
  # 10.0.0までがサブネット
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"
  # そのサブネットで起動したインスタンスにパブリックIPアドレスを自動的に割り当てる
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.tech-blog.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
}

# vpcとインターネットの接続のため
resource "aws_internet_gateway" "tech-blog" {
  vpc_id = aws_vpc.tech-blog.id
}

# インターネットゲートウェイからネットワークにデータを流すため、ルーティング情報を管理するルートテーブルが必要
# ローカルルートが自動作成されvpc内で通信できるようになる　これはterraformでも管理はできない
# ルートのテーブル
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tech-blog.id
}

# ルートはルートテーブルの1レコード
# destination_cidr_blockで出口はインターネットなので、そのどこにもいけるということ
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.tech-blog.id
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
  vpc_id                  = aws_vpc.tech-blog.id
  cidr_block              = "10.0.65.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.tech-blog.id
  cidr_block              = "10.0.66.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
}

# マルチAZのためテーブルを２つ用意
resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.tech-blog.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.tech-blog.id
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
  depends_on = [aws_internet_gateway.tech-blog]
}

resource "aws_eip" "nat_gateway_1" {
  vpc        = true
  depends_on = [aws_internet_gateway.tech-blog]
}

# NATの定義
resource "aws_nat_gateway" "nat_gateway_0" {
  # eipをNATに割り当て
  allocation_id = aws_eip.nat_gateway_0.id
  # NATはプライベートじゃなくpublicサブネットに置く
  subnet_id = aws_subnet.public_0.id
  # 実はpublicにいるinternet_gatewayに依存している
  depends_on = [aws_internet_gateway.tech-blog]
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_gateway_1.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.tech-blog]
}
