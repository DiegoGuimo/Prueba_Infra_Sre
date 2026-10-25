# 04 — Runbook de Despliegue

> Procedimiento paso a paso para desplegar el stack desde cero. Cubre el entorno de validación (LocalStack) y notas para AWS real.

---

## 1. Prerrequisitos

| Herramienta | Versión | Verificar |
| --- | --- | --- |
| Docker Desktop | >= 24 | `docker --version` |
| Terraform | >= 1.6 | `terraform version` |
| AWS CLI v2 | >= 2.x | `aws --version` |
| Python | >= 3.11 | `python --version` |
| LocalStack CLI | >= 3.x | `localstack --version` |
| tflocal | — | `tflocal --version` |

Instalación rápida (Windows):
```powershell
winget install Docker.DockerDesktop HashiCorp.Terraform Amazon.AWSCLI
pip install localstack terraform-local awscli-local
```

---

## 2. Despliegue en LocalStack (entorno de validación)

### 2.1 Preparar dependencias de la Lambda
El handler importa la librería `redis`, que debe empaquetarse junto al código:
```powershell
cd lambda
pip install redis -t .
cd ..
```

### 2.2 Levantar Redis (contenedor Docker)
ElastiCache no está en la edición gratuita de LocalStack, por lo que se usa un Redis en Docker:
```powershell
docker run -d --name redis-sre -p 6379:6379 redis:7-alpine
```

Obtener la IP del contenedor Redis (la Lambda la usa como `REDIS_HOST`):
```powershell
docker inspect redis-sre --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```
Colocar esa IP en `terraform/terraform.tfvars` → `redis_external_host`.

### 2.3 Levantar LocalStack
```powershell
localstack start -d
Start-Sleep -Seconds 25
localstack status services
```

> La primera vez pide un auth token gratuito (crear cuenta en app.localstack.cloud y `localstack auth set-token <token>`).

### 2.4 Desplegar el stack
```powershell
cd terraform
tflocal init
tflocal apply -auto-approve
```

### 2.5 Verificar
```powershell
tflocal output api_process_url_localstack
```

---

## 3. Validación funcional
```powershell
$URL = (tflocal output -raw api_process_url_localstack)

# Primera llamada: MISS
curl.exe -i -X POST "$URL" -H "Content-Type: application/json" -d '{\"data\":\"demo\"}'

# Segunda llamada idéntica: HIT
curl.exe -i -X POST "$URL" -H "Content-Type: application/json" -d '{\"data\":\"demo\"}'

# Objetos en S3
aws --endpoint-url=http://localhost:4566 s3 ls s3://(tflocal output -raw s3_bucket_name)/results/ --recursive
```

---

## 4. Despliegue en AWS real (notas)

El mismo código sirve para AWS real con estos cambios:

1. En `terraform.tfvars`:
   ```hcl
   use_elasticache     = true
   redis_external_host = ""
   ```
   Esto crea ElastiCache real en vez del Redis de Docker.

2. Empaquetar la dependencia `redis` en el zip (igual que en 2.1) o usar una Lambda Layer.

3. Usar `terraform` en lugar de `tflocal`, con credenciales AWS configuradas.

4. **Costo:** NAT Gateway y ElastiCache cobran por hora. Ejecutar `terraform destroy` tras capturar evidencias.

---

## 5. Variables de entorno útiles (PowerShell)
Al abrir una terminal nueva, para usar el AWS CLI nativo contra LocalStack:
```powershell
$env:HOME = $env:USERPROFILE
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

---

## 6. Problemas comunes

| Síntoma | Causa | Solución |
| --- | --- | --- |
| `Could not connect to localhost:4566` | LocalStack no está arriba | `localstack start -d` y esperar |
| Segunda llamada da MISS en vez de HIT | Lambda no alcanza Redis | Verificar IP de Redis en `terraform.tfvars` |
| `ModuleNotFoundError: redis` | Falta la dependencia en el zip | `pip install redis -t .` en `lambda/` |
| `apigatewayv2 not included in license` | HTTP API es Pro en LocalStack | Ya resuelto: se usa REST API v1 |
| Primer `curl` da 502 | Cold start de la Lambda | Reintentar; la segunda responde |
