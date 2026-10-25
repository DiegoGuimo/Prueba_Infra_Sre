# ===========================================================================
# SECURITY GROUPS — implementa docs/01-diseno.md §2.4 y §4.2 (seguridad)
#   - SG Lambda: sin ingress; egress a Redis (6379) y HTTPS (443)
#   - SG Redis : ingress 6379 SOLO desde el SG de Lambda; sin egress abierto
# ===========================================================================

# ---------------------------------------------------------------------------
# SG Lambda
# ---------------------------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-sg-lambda"
  description = "SG de la Lambda: egress a Redis y a servicios AWS via HTTPS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg-lambda"
  }
}

# Egress: Lambda -> Redis en el puerto 6379 (hacia el SG de Redis)
resource "aws_security_group_rule" "lambda_egress_redis" {
  type                     = "egress"
  from_port                = var.redis_port
  to_port                  = var.redis_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.redis.id
  description              = "Lambda a Redis 6379"
}

# Egress: Lambda -> servicios AWS via HTTPS (S3 por VPC Endpoint, CloudWatch, etc.)
resource "aws_security_group_rule" "lambda_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.lambda.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Lambda a servicios AWS via HTTPS"
}

# ---------------------------------------------------------------------------
# SG Redis
# ---------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-sg-redis"
  description = "SG de Redis: ingress 6379 solo desde el SG de Lambda"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg-redis"
  }
}

# Ingress: Redis acepta 6379 ÚNICAMENTE desde el SG de Lambda (nunca 0.0.0.0/0)
resource "aws_security_group_rule" "redis_ingress_lambda" {
  type                     = "ingress"
  from_port                = var.redis_port
  to_port                  = var.redis_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = aws_security_group.lambda.id
  description              = "Redis acepta 6379 solo desde SG Lambda"
}
