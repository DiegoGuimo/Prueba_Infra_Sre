"""
Lambda de procesamiento con caché Redis y persistencia en S3.

Flujo (ver docs/01-diseno.md §3.2):
  1. Parsea el body del request (API Gateway HTTP API, payload v2.0).
  2. Genera una cache key determinística (SHA-256 del body normalizado).
  3. Consulta Redis:
       - HIT  -> devuelve el valor cacheado con header X-Cache: HIT.
       - MISS -> procesa, guarda en S3 (results/<fecha>/<id>.json),
                 escribe en Redis con TTL y devuelve X-Cache: MISS.
  4. Cualquier excepción -> HTTP 500 descriptivo + log estructurado.

Variables de entorno:
  REDIS_HOST  - endpoint del nodo Redis
  REDIS_PORT  - puerto de Redis (default 6379)
  S3_BUCKET   - nombre del bucket de resultados
  CACHE_TTL   - TTL en segundos para las keys (default 60)
"""

import hashlib
import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone

import boto3
import redis

# --------------------------------------------------------------------------
# Configuración y clientes (fuera del handler para reutilizar conexiones
# entre invocaciones en caliente).
# --------------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
S3_BUCKET = os.environ.get("S3_BUCKET", "")
CACHE_TTL = int(os.environ.get("CACHE_TTL", "60"))

s3_client = boto3.client("s3")

# Cliente Redis con timeouts cortos para no colgar la Lambda si Redis no responde.
redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    socket_connect_timeout=2,
    socket_timeout=2,
    decode_responses=True,
)


def _log(request_id, cache, execution_time_ms, s3_key="", error=""):
    """Emite un log estructurado en JSON a CloudWatch."""
    logger.info(
        json.dumps(
            {
                "request_id": request_id,
                "cache": cache,
                "execution_time_ms": execution_time_ms,
                "s3_key": s3_key,
                "error": error,
            }
        )
    )


def _make_cache_key(body_str):
    """Clave de caché determinística a partir del body normalizado."""
    return "cache:" + hashlib.sha256(body_str.encode("utf-8")).hexdigest()


def _process(payload):
    """
    Transformación de ejemplo (libre según el enunciado):
    invierte el string 'data' si existe, y añade metadatos.
    """
    data = payload.get("data", "")
    transformed = data[::-1] if isinstance(data, str) else data
    return {
        "input": payload,
        "transformed": transformed,
        "processed_at": datetime.now(timezone.utc).isoformat(),
    }


def _response(status_code, cache_state, body):
    """Construye la respuesta con el header X-Cache obligatorio."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "X-Cache": cache_state,
        },
        "body": json.dumps(body),
    }


def handler(event, context):
    start = time.time()
    request_id = getattr(context, "aws_request_id", str(uuid.uuid4()))

    try:
        # API Gateway HTTP API (payload v2.0) entrega el body como string.
        raw_body = event.get("body") or "{}"
        try:
            payload = json.loads(raw_body)
        except json.JSONDecodeError:
            raise ValueError("El body no es un JSON válido")

        cache_key = _make_cache_key(json.dumps(payload, sort_keys=True))

        # Diagnóstico explícito de conectividad a Redis (se registra en CloudWatch).
        logger.info(json.dumps({
            "request_id": request_id,
            "diag": "redis_config",
            "redis_host": REDIS_HOST,
            "redis_port": REDIS_PORT,
            "cache_key": cache_key,
        }))
        try:
            ping_ok = redis_client.ping()
            logger.info(json.dumps({"request_id": request_id, "diag": "redis_ping", "ok": bool(ping_ok)}))
        except Exception as ping_exc:  # noqa: BLE001
            logger.error(json.dumps({"request_id": request_id, "diag": "redis_ping_error", "error": str(ping_exc)}))

        # 1. Consultar Redis (cache hit).
        cached = redis_client.get(cache_key)
        logger.info(json.dumps({
            "request_id": request_id,
            "diag": "redis_get",
            "found": cached is not None,
        }))
        if cached is not None:
            elapsed = int((time.time() - start) * 1000)
            _log(request_id, "HIT", elapsed)
            return _response(200, "HIT", json.loads(cached))

        # 2. Cache miss: procesar.
        result = _process(payload)
        result_id = str(uuid.uuid4())
        date_prefix = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        s3_key = f"results/{date_prefix}/{result_id}.json"

        # 3. Persistir en S3.
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(result).encode("utf-8"),
            ContentType="application/json",
        )

        # 4. Escribir en Redis con TTL explícito.
        redis_client.setex(cache_key, CACHE_TTL, json.dumps(result))
        # Confirmar que la key quedó escrita y con TTL.
        ttl_check = redis_client.ttl(cache_key)
        logger.info(json.dumps({
            "request_id": request_id,
            "diag": "redis_setex",
            "ttl_after_write": ttl_check,
        }))

        elapsed = int((time.time() - start) * 1000)
        _log(request_id, "MISS", elapsed, s3_key=s3_key)
        return _response(200, "MISS", result)

    except Exception as exc:  # noqa: BLE001 - se registra y se devuelve 500
        elapsed = int((time.time() - start) * 1000)
        _log(request_id, "ERROR", elapsed, error=str(exc))
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json", "X-Cache": "ERROR"},
            "body": json.dumps({"error": "Internal Server Error", "detail": str(exc)}),
        }
