# 06 — Matriz de Requerimientos y Trazabilidad

> Trazabilidad entre cada requerimiento del enunciado, su implementación propuesta, la evidencia esperada, el componente responsable y el estado de cumplimiento.
>
> **Leyenda de estado:** 🔵 Planificado · 🟡 En implementación · 🟢 Cumplido · ⚪ Opcional

---

## 1. Requerimientos Funcionales

| ID | Requisito funcional | Implementación propuesta | Evidencia esperada | Componente responsable | Estado |
| --- | --- | --- | --- | --- | --- |
| RF-01 | Exponer endpoint `POST /process` | Ruta `POST /process` en HTTP API con stage `$default` | `curl -i` devuelve HTTP 200 | API Gateway | 🔵 |
| RF-02 | API Gateway invoca Lambda vía proxy | Integración `AWS_PROXY` hacia la Lambda | Request llega al handler (log) | API Gateway + Lambda | 🔵 |
| RF-03 | Generar cache key desde el body | Hash SHA-256 del body normalizado | Misma entrada → misma key (log) | Lambda | 🔵 |
| RF-04 | Consultar Redis antes de procesar | Cliente `redis-py` consulta la key | Log muestra lookup en Redis | Lambda + Redis | 🔵 |
| RF-05 | Retornar HIT si el dato existe | Si `GET key` devuelve valor → responder cacheado | 2ª llamada: header `X-Cache: HIT` | Lambda + Redis | 🔵 |
| RF-06 | Retornar MISS si no existe | Si `GET key` vacío → procesar y persistir | 1ª llamada: header `X-Cache: MISS` | Lambda + Redis | 🔵 |
| RF-07 | Guardar resultado en S3 en MISS | `PutObject` en `results/<fecha>/<id>.json` | `aws s3 ls` muestra el objeto | Lambda + S3 | 🔵 |
| RF-08 | Escribir en Redis con TTL 60s | `SETEX key 60 valor` | Key expira tras 60s (3ª llamada MISS) | Lambda + Redis | 🔵 |
| RF-09 | Incluir header `X-Cache` siempre | Header añadido en toda respuesta (HIT/MISS) | Header presente en ambos casos | Lambda | 🔵 |
| RF-10 | Errores → HTTP 500 + log | `try/except` → 500 descriptivo + log estructurado | Body inválido devuelve 500 + log CloudWatch | Lambda + CloudWatch | 🔵 |

---

## 2. Requerimientos No Funcionales

| ID | Requisito no funcional | Implementación propuesta | Evidencia esperada | Componente responsable | Estado |
| --- | --- | --- | --- | --- | --- |
| RNF-01 | Infraestructura 100% IaC, un solo `apply` | Todo el stack en Terraform, sin pasos manuales | `terraform apply` crea todo | Terraform | 🔵 |
| RNF-02 | IAM de mínimo privilegio | Rol Lambda solo con permisos usados (S3 prefijo, logs, ENI) | Policy sin `*` innecesarios | IAM | 🔵 |
| RNF-03 | Red segura (subnets privadas, SG segmentados) | Lambda/Redis en privadas; SG Redis solo desde SG Lambda:6379 | Sin IP pública; reglas SG | VPC + SG | 🔵 |
| RNF-04 | S3 privado (BPA x4 + bucket policy) | Block Public Access completo + policy al rol Lambda | Config del bucket | S3 | 🔵 |
| RNF-05 | VPC Endpoint S3 (sin salir a internet) | Endpoint Gateway + ruta en RT privada | Tráfico S3 por endpoint | VPC Endpoint | 🔵 |
| RNF-06 | Throttling en API Gateway (rate + burst) | Límites de rate y burst a nivel de stage | Config de throttling | API Gateway | 🔵 |
| RNF-07 | Observabilidad (access logs + logs Lambda) | Access logs API + logs JSON de Lambda en CloudWatch | Log groups con eventos | CloudWatch | 🔵 |
| RNF-08 | Reproducibilidad (variables parametrizadas) | `variables.tf` + `terraform.tfvars` | Deploy reproducible | Terraform | 🔵 |
| RNF-09 | Código limpio y documentado | Handler legible + README + docs | Revisión de código | Lambda + docs | 🔵 |
| RNF-10 | Secrets fuera del código | Sin credenciales en `.tf` ni handler | Inspección del repo | Todo | 🔵 |

---

## 3. Mapeo Requerimiento → Criterio de evaluación

Relación entre los requerimientos y los criterios de calificación del enunciado, para asegurar que cada porcentaje queda cubierto.

| Criterio (peso) | Requerimientos que lo sustentan |
| --- | --- |
| Infraestructura como código (30%) | RNF-01, RNF-08, RF-01..RF-02 |
| Seguridad de red (25%) | RNF-02, RNF-03, RNF-04, RNF-05, RNF-10 |
| Correctitud funcional (25%) | RF-03..RF-10 |
| Calidad y documentación (20%) | RNF-07, RNF-09 + README y docs |

---

## 4. Requerimientos opcionales (mejoras)

| ID | Mejora | Valor que aporta | Estado |
| --- | --- | --- | --- |
| OPT-01 | Pipeline CI/CD (fmt, validate, tfsec, checkov, plan, apply, smoke) | Despliegue automatizado y gates de seguridad | ⚪ |
| OPT-02 | Remote state (S3 + DynamoDB lock) | Estado compartido y bloqueo concurrente | ⚪ |
| OPT-03 | KMS / Secrets Manager | Cifrado gestionado y secrets si Redis usa auth | ⚪ |
| OPT-04 | Dashboards y alarmas CloudWatch | Observabilidad proactiva (SRE) | ⚪ |
| OPT-05 | NAT Gateway por AZ + Redis con réplica | Mayor resiliencia | ⚪ |

---

## 5. Evidencias a recolectar (resumen para `evidence/`)

| Evidencia | Comando / acción | Requerimientos que valida |
| --- | --- | --- |
| `X-Cache: MISS` | 1er `curl -i POST /process` | RF-06, RF-09 |
| `X-Cache: HIT` | 2º `curl -i POST /process` idéntico | RF-05, RF-09 |
| Objeto en S3 | `aws s3 ls .../results/ --recursive` | RF-07 |
| Expiración TTL | 3er `curl` tras 60s → MISS | RF-08 |
| Error 500 | `curl` con body inválido | RF-10 |
| Logs CloudWatch | Consola/`aws logs` | RNF-07 |
