# ===========================================================================
# API GATEWAY (REST API v1) — implementa docs/01-diseno.md §3.1
#   NOTA: se usa REST API (v1) en lugar de HTTP API (v2) porque la edicion
#   gratuita de LocalStack NO soporta apigatewayv2. REST API cumple los mismos
#   requisitos del enunciado: ruta POST /process con integracion proxy,
#   throttling (rate + burst), CORS y access logs. En AWS real podria usarse
#   cualquiera de las dos; aqui se elige REST por compatibilidad con LocalStack.
#   - REST API + recurso /process + metodo POST (AWS_PROXY)
#   - Metodo OPTIONS para CORS
#   - Stage con throttling y access logs
# ===========================================================================

resource "aws_api_gateway_rest_api" "http" {
  name        = "${var.project_name}-api"
  description = "API REST de entrada al servicio de procesamiento"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

# Recurso /process
resource "aws_api_gateway_resource" "process" {
  rest_api_id = aws_api_gateway_rest_api.http.id
  parent_id   = aws_api_gateway_rest_api.http.root_resource_id
  path_part   = "process"
}

# ---------------------------------------------------------------------------
# Metodo POST /process  (integracion proxy con Lambda)
# ---------------------------------------------------------------------------
resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.http.id
  resource_id   = aws_api_gateway_resource.process.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.http.id
  resource_id             = aws_api_gateway_resource.process.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.processor.invoke_arn
}

# ---------------------------------------------------------------------------
# Metodo OPTIONS /process  (CORS)
# ---------------------------------------------------------------------------
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.http.id
  resource_id   = aws_api_gateway_resource.process.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.http.id
  resource_id = aws_api_gateway_resource.process.id
  http_method = aws_api_gateway_method.options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.http.id
  resource_id = aws_api_gateway_resource.process.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.http.id
  resource_id = aws_api_gateway_resource.process.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# ---------------------------------------------------------------------------
# Deployment + Stage
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigw/${var.project_name}-api"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-apigw-logs"
  }
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.http.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.process.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.options,
  ]
}

resource "aws_api_gateway_stage" "default" {
  rest_api_id   = aws_api_gateway_rest_api.http.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "dev"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId  = "$context.requestId"
      ip         = "$context.identity.sourceIp"
      httpMethod = "$context.httpMethod"
      path       = "$context.path"
      status     = "$context.status"
    })
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }
}

# Throttling (rate + burst) a nivel de stage/metodo.
resource "aws_api_gateway_method_settings" "throttle" {
  rest_api_id = aws_api_gateway_rest_api.http.id
  stage_name  = aws_api_gateway_stage.default.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit
  }
}

# Permiso para que API Gateway invoque la Lambda.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.http.execution_arn}/*/*"
}
