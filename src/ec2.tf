resource "aws_instance" "for_operation" {
  ami                   = "ami-0c3fd0f5d33134a76"
  # operation用だけのためmicroでOK
  instance_type         = "t3.micro"
  iam_instance_profile  = aws_iam_instance_profile.ec2_for_ssm.name
  # プライベートサブネットに配置し外部アクセスを遮断
  subnet_id             = aws_subnet.private_0.id
  user_data             = file("./shell/user_data.sh")
}

output "operation_instance_id" {
  value  = aws_instance.for_operation.id
}
