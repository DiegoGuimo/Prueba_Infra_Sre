# 03 — Observabilidad y Monitoreo (SRE)

> Describe la estrategia de logs, métricas y alarmas. Satisface el requerimiento RNF-07 (observabilidad) y aporta al criterio "Calidad y documentación" (20%).
>
> **Enfoque SRE:** poder responder *¿funciona?, ¿es rápido?, ¿falla?* con los datos que emite el sistema.

---

## 1. Resumen

| Señal | Fuente | Dónde se implementa | Estado |
| --- | --- | --- | --- |
| Access logs | API Gateway | `apigw.tf` (log group + `access_log_settings`) | ✅ Implementado |
| Logs de aplicación | Lambda | `handler.py` (JSON) + `lambda.tf` (log group) | ✅ Implementado |
| Métricas de servicio | CloudWatch (automáticas) | Nativas de API GW / Lambda / ElastiCache | ✅ Disponibles |
| Alarmas | CloudWatch | — | ⚪ Opcional (OPT-04) |
| Dashboard | CloudWatch | — | ⚪ Opcional (OPT-04) |

---

## 2. Logs

### 2.1 Access logs de API Gateway
El stage `$default` escribe access logs en el log group `/aws/apigw/sre-prueba-api` en formato JSON (`apigw.tf`). Cada entrada incluye:

| Campo | Significado |
| --- | --- |
| `requestId` | Identificador único del request |
| `ip` | IP de origen del cliente |
| `requestTime` | Marca temporal |
| `httpMethod` | Método HTTP |
| `routeKey` | Ruta invocada (`POST /process`) |
| `status` | Código de respuesta |
| `responseLength` | Tamaño de la respuesta |
| `integrationErr` | Mensaje de error de integración (si lo hubo) |

Permite auditar tráfico, detectar 4XX/5XX y correlacionar con los logs de la Lambda vía `requestId`.

### 2.2 Logs estructurados de la Lambda
El handler emite un log JSON por invocación al log group `/aws/lambda/sre-prueba-processor`:

```json
{
  "request_id": "abc-123",
  "cache": "MISS",
  "execution_time_ms": 42,
  "s3_key": "results/2026-10-23/uuid.json",
  "error": ""
}
```

Ventajas:
- El campo `cache` permite medir el **cache hit ratio** filtrando por `HIT`/`MISS`.
- `execution_time_ms` da visibilidad de latencia a nivel de aplicación.
- `s3_key` traza qué objeto generó cada MISS.
- `error` queda poblado en las respuestas 500, facilitando el diagnóstico.

Retención configurada a 7 días en ambos log groups (ajustable por variable en producción).

### 2.3 Consulta rápida de logs
```bash
# LocalStack
awslocal logs tail /aws/lambda/sre-prueba-processor --follow
awslocal logs tail /aws/apigw/sre-prueba-api --follow

# AWS real
aws logs tail /aws/lambda/sre-prueba-processor --follow
```

---

## 3. Métricas relevantes (CloudWatch)

Estas métricas las emiten los servicios de forma automática; no requieren código adicional.

### 3.1 API Gateway
| Métrica | Qué indica | Umbral de atención |
| --- | --- | --- |
| `4XXError` | Errores de cliente | Pico sostenido |
| `5XXError` | Errores de servidor | > 1% de requests |
| `Latency` | Latencia total | p99 alto |
| `Count` | Volumen de tráfico | Base para capacidad |

### 3.2 Lambda
| Métrica | Qué indica |
| --- | --- |
| `Invocations` | Nº de ejecuciones |
| `Duration` | Tiempo de ejecución |
| `Errors` | Fallos (correlacionar con 500) |
| `Throttles` | Límite de concurrencia alcanzado |

### 3.3 ElastiCache Redis
| Métrica | Qué indica |
| --- | --- |
| `CPUUtilization` | Carga del nodo |
| `DatabaseMemoryUsagePercentage` | Memoria usada |
| `Evictions` | Keys expulsadas por falta de memoria |
| `CurrConnections` | Conexiones activas |
| `CacheHits` / `CacheMisses` | Eficacia de la caché |

---

## 4. Alarmas propuestas (opcional — OPT-04)

Si se implementa la mejora de alarmas, estas serían las de alta prioridad:

| Alarma | Condición | Acción |
| --- | --- | --- |
| Lambda errores | `Errors` > 5 en 5 min | Notificar (SNS) |
| API 5XX | `5XXError` > 1% en 5 min | Notificar |
| Redis CPU | `CPUUtilization` > 80% | Revisar carga / escalar |
| Redis memoria | `DatabaseMemoryUsagePercentage` > 75% | Revisar TTL / escalar |

> No se implementan por defecto porque el enunciado no las exige y añaden recursos (SNS) fuera del alcance mínimo. Se dejan diseñadas para habilitarlas rápido.

---

## 5. Los cuatro "golden signals" aplicados

| Señal (SRE) | Cómo se mide aquí |
| --- | --- |
| **Latencia** | `Duration` de Lambda + `Latency` de API GW + `execution_time_ms` del log |
| **Tráfico** | `Count` de API GW, `Invocations` de Lambda |
| **Errores** | `5XXError`, `Errors`, logs con `cache: ERROR` |
| **Saturación** | CPU/memoria/evictions de Redis, `Throttles` de Lambda |

---

## 6. Checklist de observabilidad (Go Live)
- [ ] Access logs de API Gateway visibles en su log group.
- [ ] Logs JSON de la Lambda visibles y parseables.
- [ ] Correlación posible por `request_id`.
- [ ] Métricas nativas visibles en CloudWatch.
- [ ] (Opcional) Alarmas y dashboard habilitados.
