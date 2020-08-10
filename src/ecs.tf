# ECSクラスタは、Docker コンテナを実行するホストサーバーを、論理的に束ねるリソース
resource "aws_ecs_cluster" "tech-blog" {
  name = "tech-blog"
}

# コンテナの実行単位 は「タスク」で「タスク定義」から生成される　
# クラスがタスク定義、タスクがインスタンスという関係
# たとえば、Railsアプリケーションの前段にnginxを配置する場合、ひとつのタスクの中でRails コンテナとnginxコンテナが実行される
resource "aws_ecs_task_definition" "tech-blog" {
  # タスク定義名のプレフィックスのこと tech-blog:1のようになる
  family = "tech-blog"
  # cpuに256を指定する場合、memoryで指定できる値は512・1024・2048のいずれか
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  # 実際にタスクで実行するコンテナの定義
  container_definitions = file("./container/container_definitions.json")
  # Docker コンテナがCloudWatch Logs にログを投げられるようにする（FARGATEではコンテナのログを直接確認できないため)
  execution_role_arn = module.ecs_task_execution_role.iam_role_arn
}

# ECSサービスは起動するタスクの数を定義でき、指定した数のタスクを維持　なんらかの理由でタスクが終了してしまった場合、自動的に新しいタスクを起動してくれる
# またECSサービスはALBとの橋渡し役にもなり、インターネットからのリクエストはALBで受けそのリクエストをコンテナにフォワードさせる
resource "aws_ecs_service" "tech-blog" {
  name            = "tech-blog"
  cluster         = aws_ecs_cluster.tech-blog.arn
  task_definition = aws_ecs_task_definition.tech-blog.arn
  # 2個以上コンテナ起動する
  desired_count = 2
  launch_type   = "FARGATE"
  # latestが最新ではないので明示的にする必要あり
  platform_version = "1.3.0"
  # タスク起動時のヘルスチェック猶予期間 0だとタスクの起動と終了が無限に続く可能性あり
  health_check_grace_period_seconds = 60

  # サブネットとセキュリティグループを設定
  network_configuration {
    assign_public_ip = false
    security_groups  = [module.nginx_sg.security_group_id]

    subnets = [
      aws_subnet.private_0.id,
      aws_subnet.private_1.id,
    ]
  }

  # load_balancerでターゲットグループとコンテナの名前・ポート番号を指定し、ロードバランサーと関連付ける
  load_balancer {
    target_group_arn = aws_lb_target_group.tech-blog.arn
    container_name   = "tech-blog"
    container_port   = 80
  }

  # 　Fargate の場合、デプロイのたびにタスク定義が更新され、plan時に差分が出るのを無視する
  lifecycle {
    ignore_changes = [task_definition]
  }
}


# CloudWatchLogsでECSのログを取る
resource "aws_cloudwatch_log_group" "for_ecs" {
  name = "/ecs/tech-blog"
  # ログの保持期間
  retention_in_days = 180
}
