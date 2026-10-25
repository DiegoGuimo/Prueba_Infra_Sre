terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Provider AWS.
# Para LocalStack se usa el wrapper `tflocal`, que inyecta automáticamente
# los endpoints locales y credenciales dummy. Por eso aquí NO se fijan
# endpoints: el mismo código sirve para AWS real y para LocalStack.
provider "aws" {
  region = var.aws_region

  # Etiquetas por defecto aplicadas a todos los recursos que las soporten.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}
