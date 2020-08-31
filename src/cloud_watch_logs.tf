# CloudWatchLogsでECSのログを取る
resource "aws_cloudwatch_log_group" "for_ecs_vue" {
  name = "/ecs/vue"
  # ログの保持期間
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "for_ecs_go" {
  name = "/ecs/go"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "operation" {
  name = "/operation"
  retention_in_days = 14
}
