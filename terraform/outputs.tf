# ===========================================================================
# OUTPUTS — red (Fase 2) + servicios (Fase 3)
#   Los nombres coinciden con el contrato de BRIEF-COPILOT.md §2.
# ===========================================================================

# --- Servicios (Fase 3) ---------------------------------------------------

output "api_endpoint" {
  description = "URL base del API Gateway REST (añadir /process para invocar)."
  value       = aws_api_gateway_stage.default.invoke_url
}

output "api_process_url_localstack" {
  description = "URL completa de POST /process para LocalStack (endpoint 4566)."
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.http.id}/${aws_api_gateway_stage.default.stage_name}/_user_request_/process"
}

output "s3_bucket_name" {
  description = "Nombre del bucket de resultados."
  value       = aws_s3_bucket.results.bucket
}

output "redis_endpoint" {
  description = "Endpoint del nodo Redis (ElastiCache o Redis externo en Docker)."
  value       = var.use_elasticache ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : var.redis_external_host
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda."
  value       = aws_lambda_function.processor.function_name
}

# --- Red (Fase 2) ---------------------------------------------------------

output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas (Lambda y Redis)."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "ID del NAT Gateway."
  value       = aws_nat_gateway.main.id
}

output "s3_vpc_endpoint_id" {
  description = "ID del VPC Endpoint Gateway para S3."
  value       = aws_vpc_endpoint.s3.id
}

output "lambda_security_group_id" {
  description = "ID del Security Group de la Lambda."
  value       = aws_security_group.lambda.id
}

output "redis_security_group_id" {
  description = "ID del Security Group de Redis."
  value       = aws_security_group.redis.id
}
