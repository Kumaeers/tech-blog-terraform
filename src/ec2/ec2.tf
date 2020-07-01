resource "aws_instance" "sandbox" {
  ami = "ami-785c491f"
  instance_type = "t2.micro"
  # remote_stateのoutputsを指定している
  subnet_id = "data.terraform_remote_state.vpc.outputs.public_subnet_id"
}

provider "aws" {
  region = "ap-northeast-1"
}

# remote_state を設定しvpc という名前で参照できるようにする
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
  bucket = "kumaeers-terraform"
  key = "src/vpc/terraform.tfstate"
  region = "ap-northeast-1"
  }
}

terraform {
  backend "s3" {
    bucket = "kumaeers-terraform"
    # キー名はvpc のものとかぶらないように
    key = "src/ec2/terraform.tfstate"
    region = "ap-northeast-1"
  }
}
