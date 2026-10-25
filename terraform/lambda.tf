# ===========================================================================
# LAMBDA — implementa docs/01-diseno.md §3.2 y §4.1 (IAM mínimo privilegio)
#   - Rol IAM acotado: logs, ENI (VPC) y S3 solo sobre results/*
#   - Log group dedicado
#   - Función en subnets privadas, asociada al SG de Lambda
#   - Empaquetado del código vía archive_file
# ===========================================================================

# ---------------------------------------------------------------------------
# Empaquetado del código de la Lambda.
#   NOTA: el handler importa 'redis'. Para AWS real, las dependencias deben
#   incluirse en el zip o en una Lambda Layer (ver docs/04-runbook-despliegue).
#   En LocalStack suele bastar con el handler para validar el flujo.
# ---------------------------------------------------------------------------
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda.zip"
}

# ---------------------------------------------------------------------------
# Rol IAM de la Lambda (trust policy)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# ---------------------------------------------------------------------------
# Política de permisos mínimos
#   - Logs en su propio log group
#   - Gestión de ENI (requisito de Lambda en VPC)
#   - S3: solo sobre el prefijo results/* del bucket de resultados
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_permissions" {
  # CloudWatch Logs
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  # ENI management para Lambda en VPC (requiere recursos "*" por diseño de AWS)
  statement {
    sid    = "VpcEni"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }

  # S3: escritura/lectura solo sobre results/* y listado del bucket
  statement {
    sid    = "S3Results"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.results.arn}/results/*"]
  }

  statement {
    sid       = "S3List"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.results.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ---------------------------------------------------------------------------
# Log group de la Lambda
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-processor"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-lambda-logs"
  }
}

# ---------------------------------------------------------------------------
# Función Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-processor"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  filename      = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout       = 10
  memory_size   = 256

  # Despliegue en subnets privadas, con el SG de Lambda.
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REDIS_HOST = var.use_elasticache ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : var.redis_external_host
      REDIS_PORT = tostring(var.redis_port)
      S3_BUCKET  = aws_s3_bucket.results.bucket
      CACHE_TTL  = tostring(var.cache_ttl_seconds)
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = {
    Name = "${var.project_name}-processor"
  }
}
