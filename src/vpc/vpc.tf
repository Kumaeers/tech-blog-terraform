resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"
}

# リソース名とリソースの識別名　
# 同じリソース元で別のリソースということがあるためリソースの識別名をつける
resource "aws_subnet" "public_subnet" {
  vpc_id = "aws_vpc.vpc.id"
  cidr_block = "10.0.16.0/20"
  availability_zone = "ap-northeast-1a"
}

provider "aws" {
  region = "ap-northeast-1"
}
# outputで他のディレクトリからもこの名前で参照できる
# subnet のid をvalue にセット
output "public_subnet_id" {
  value = "aws_subnet.public_subnet.id"
}

terraform {
  backend "s3" {
    bucket = "kumaeers-terraform"
    # key をかぶらないように
    # ディレクトリ構成と同じようにするとgood
    key = "src/vpc/terraform.tfstate"
    region = "ap-northeast-1"
  }
}
