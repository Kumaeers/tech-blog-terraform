# ECR
resource "aws_ecr_repository" "tech-blog" {
  name = "tech-blog"
}

# ライフサイクルポリシーでイメージの数が増えすぎないように制御
resource "aws_ecr_lifecycle_policy" "tech-blog" {
  repository = aws_ecr_repository.tech-blog.name

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
