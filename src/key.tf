# resource "aws_kms_key" "example" {
#   description             = "Example Customer Master Key"
#   # 自動ローテーション
#   enable_key_rotation     = true
#   # カスタマーマスターキーをが有効か無効か
#   is_enabled              = true
#   # カスタマーマスターキーの削除は推奨されない 消したらこのカスタマーキーで作成した暗号は復号できなくなるため
#   deletion_window_in_days = 30
# }

# # カスタマーマスターキーにはそれぞれUUIDが割り当てられますが、人間には分かりづらい　そこでエイリアスを設定し、どういう用途で使われているか識別しやすくする
# resource "aws_kms_alias" "example" {
#   name          = "alias/example"
#   target_key_id = aws_kms_key.example.key_id
# }
