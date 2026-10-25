# Valores de las variables. Ajusta según tu entorno.
# Estos defaults están pensados para LocalStack (us-east-1).

project_name = "sre-prueba"
environment  = "dev"
owner        = "sre-candidate"
aws_region   = "us-east-1"

vpc_cidr             = "10.20.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

redis_node_type = "cache.t3.micro"
redis_port      = 6379

api_throttle_rate_limit  = 50
api_throttle_burst_limit = 100

cache_ttl_seconds = 60

# --- Modo LocalStack (Opción A: Redis en contenedor Docker) ---------------
# ElastiCache no está disponible en LocalStack free, por eso se desactiva
# y la Lambda apunta a un Redis externo. En AWS real: use_elasticache = true.
use_elasticache     = false
# La Lambda (dentro de LocalStack, red bridge) alcanza el Redis de Docker
# por su IP en la red bridge. Obtenida con:
#   docker inspect redis-sre --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
redis_external_host = "172.17.0.3"
