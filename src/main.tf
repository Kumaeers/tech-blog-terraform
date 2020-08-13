provider "aws" {
  profile = "default"
  region  = "ap-northeast-1"
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
