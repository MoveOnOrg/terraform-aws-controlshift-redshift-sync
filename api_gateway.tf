// Provides a settings of an API Gateway Account. Settings is applied region-wide per provider block.
resource "aws_api_gateway_account" "settings" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_role.arn
}
