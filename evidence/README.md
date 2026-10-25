# Evidencias de funcionamiento

Esta carpeta contiene la evidencia de que el servicio funciona end-to-end sobre LocalStack: flujo de caché (MISS/HIT), persistencia en S3 y logs de la Lambda.

## Entorno de validación

- **Plataforma:** LocalStack Community (edición gratuita) en Docker.
- **Redis:** contenedor Docker independiente (`redis:7-alpine`), porque ElastiCache no está disponible en la edición gratuita de LocalStack. La Lambda apunta a ese Redis vía variable de entorno `REDIS_HOST`.
- **API Gateway:** REST API v1 (HTTP API/v2 no está en la edición gratuita de LocalStack). Cumple los mismos requisitos: ruta `POST /process`, integración proxy, throttling, CORS y access logs.
- **Despliegue:** `tflocal apply` (Terraform apuntando a LocalStack).

## Archivos

| Archivo | Qué demuestra | Requerimiento |
| --- | --- | --- |
| `01-miss.txt` | Primera llamada a `POST /process` → `HTTP 200` + header `X-Cache: MISS` | RF-06, RF-09 |
| `02-hit.txt` | Segunda llamada idéntica → `HTTP 200` + header `X-Cache: HIT` (respuesta servida desde Redis) | RF-05, RF-09 |
| `03-s3-objetos.txt` | `aws s3 ls` mostrando los resultados persistidos bajo `results/<fecha>/<id>.json` | RF-07 |
| `04-logs-lambda.txt` | Logs estructurados de la Lambda con el flujo completo (ping a Redis, get, setex con TTL, cache HIT/MISS) | RF-10, RNF-07 |
| `05-terraform-outputs.txt` | Outputs del stack desplegado (endpoint API, bucket, endpoint Redis, etc.) | RNF-01 |
| `capturas/` | Capturas de pantalla del terminal mostrando MISS/HIT y los objetos en S3 | — |

## Cómo leer la evidencia clave

### Cache MISS → HIT
En `01-miss.txt` el header es `X-Cache: MISS` (el dato se procesa y se guarda). En `02-hit.txt`, con el **mismo** body, el header es `X-Cache: HIT` y el campo `processed_at` del cuerpo es **idéntico** al de la primera llamada: eso prueba que la respuesta vino de la caché y no se reprocesó.

### Persistencia en S3
`03-s3-objetos.txt` lista objetos con la ruta `results/<fecha>/<id>.json`, confirmando el formato de clave exigido.

### Logs de la Lambda
`04-logs-lambda.txt` muestra, por cada invocación, un log JSON con `cache` (MISS/HIT), `execution_time_ms` y `s3_key`. Se observa que el HIT tiene un tiempo de ejecución mucho menor (sirve desde Redis) que el MISS (procesa + escribe en S3 y Redis).

## Reproducir

```bash
# 1. Obtener la URL del endpoint
tflocal output api_process_url_localstack

# 2. Primera llamada (MISS) y segunda idéntica (HIT)
curl -i -X POST "<URL>" -H "Content-Type: application/json" -d '{"data":"demo"}'
curl -i -X POST "<URL>" -H "Content-Type: application/json" -d '{"data":"demo"}'

# 3. Verificar objetos en S3
aws --endpoint-url=http://localhost:4566 s3 ls s3://<bucket>/results/ --recursive
```
