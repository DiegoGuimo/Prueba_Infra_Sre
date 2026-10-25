# ===========================================================================
# ElastiCache Redis — implementa docs/01-diseno.md §3.3
#   - Subnet Group apuntando a las subnets privadas
#   - Nodo cache.t3.micro, un solo nodo (sin réplica) para la prueba
#   - Sin acceso público; SG solo desde Lambda
#   - Las keys llevan TTL explícito (lo gestiona la Lambda, 60s)
# ===========================================================================

# Se crean solo si use_elasticache = true (AWS real).
# En LocalStack (use_elasticache = false) se usa un Redis en Docker.
resource "aws_elasticache_subnet_group" "redis" {
  count      = var.use_elasticache ? 1 : 0
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-redis-subnets"
  }
}

resource "aws_elasticache_cluster" "redis" {
  count                = var.use_elasticache ? 1 : 0
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  port                 = var.redis_port
  subnet_group_name    = aws_elasticache_subnet_group.redis[0].name
  security_group_ids   = [aws_security_group.redis.id]

  # Sin snapshots/persistencia indefinida: es una caché con TTL.
  snapshot_retention_limit = 0

  tags = {
    Name = "${var.project_name}-redis"
  }
}
