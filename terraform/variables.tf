# ---------------------------------------------------------------------------
# Variables de proyecto / naming
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Prefijo de nombres para todos los recursos."
  type        = string
  default     = "sre-prueba"
}

variable "environment" {
  description = "Entorno lógico (dev/prod)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Responsable del proyecto (tag Owner)."
  type        = string
  default     = "sre-candidate"
}

variable "aws_region" {
  description = "Región de AWS (o región simulada en LocalStack)."
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Red (CIDR y zonas de disponibilidad) — ver docs/01-diseno.md §2
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Las dos AZ donde se distribuyen subnets públicas y privadas."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las 2 subnets públicas (AZ a, AZ b)."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las 2 subnets privadas (AZ a, AZ b)."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

# ---------------------------------------------------------------------------
# Redis — ver docs/01-diseno.md §3.3
# ---------------------------------------------------------------------------

variable "redis_node_type" {
  description = "Tipo de nodo de ElastiCache Redis."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_port" {
  description = "Puerto de Redis."
  type        = number
  default     = 6379
}

# ---------------------------------------------------------------------------
# API Gateway throttling — ver docs/01-diseno.md §3.1
# ---------------------------------------------------------------------------

variable "api_throttle_rate_limit" {
  description = "Rate limit (req/s) a nivel de stage."
  type        = number
  default     = 50
}

variable "api_throttle_burst_limit" {
  description = "Burst limit a nivel de stage."
  type        = number
  default     = 100
}

# ---------------------------------------------------------------------------
# Caché
# ---------------------------------------------------------------------------

variable "cache_ttl_seconds" {
  description = "TTL en segundos para las keys en Redis."
  type        = number
  default     = 60
}

# ---------------------------------------------------------------------------
# Modo de Redis (AWS real vs LocalStack)
#   - use_elasticache = true  -> crea ElastiCache (AWS real)
#   - use_elasticache = false -> usa un Redis externo (contenedor Docker),
#                                 porque ElastiCache no está en LocalStack free
# ---------------------------------------------------------------------------
variable "use_elasticache" {
  description = "Si es true crea ElastiCache (AWS real). En LocalStack se pone false y se usa un Redis externo."
  type        = bool
  default     = true
}

variable "redis_external_host" {
  description = "Host de un Redis externo (contenedor Docker) cuando use_elasticache = false."
  type        = string
  default     = ""
}
