variable "name" {
  default = "tech-blog"
}

variable "region" {
  default = "ap-northeast-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_0" {
  default = "10.0.1.0/24"
}

variable "public_subnet_1" {
  default = "10.0.2.0/24"
}
