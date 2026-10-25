# 02 — Modelo de Seguridad (DevSecOps)

> Describe los controles de seguridad implementados en el IaC y cómo cada uno satisface los requerimientos no funcionales (RNF-02 a RNF-05, RNF-10) y el criterio de evaluación "Seguridad de red" (25%).
>
> **Principio rector:** *deny by default* + *least privilege*. Nada se abre si no es estrictamente necesario para el flujo.

---

## 1. Resumen de controles

| Dominio | Control | Dónde se implementa | Requerimiento |
| --- | --- | --- | --- |
| Red | Lambda y Redis solo en subnets privadas | `vpc.tf`, `lambda.tf`, `redis.tf` | RNF-03 |
| Red | SGs segmentados (6379 solo Lambda→Redis) | `security.tf` | RNF-03 |
| Red | Tráfico a S3 por VPC Endpoint (no internet) | `vpc.tf` | RNF-05 |
| IAM | Rol Lambda de mínimo privilegio | `lambda.tf` | RNF-02 |
| Datos | S3 Block Public Access x4 | `s3.tf` | RNF-04 |
| Datos | Bucket policy restringida + deny no-TLS | `s3.tf` | RNF-04 |
| Datos | Cifrado en reposo (SSE-S3) | `s3.tf` | RNF-04 |
| Secrets | Sin credenciales en código ni `.tf` | todo | RNF-10 |

---

## 2. Seguridad de red

### 2.1 Segmentación por subnets
- **Subnets públicas** (`10.20.0.0/24`, `10.20.1.0/24`): solo alojan el NAT Gateway y el Internet Gateway. No hay cómputo expuesto.
- **Subnets privadas** (`10.20.10.0/24`, `10.20.11.0/24`): alojan Lambda y Redis. Sin IP pública, sin ruta de entrada desde internet.

### 2.2 Security Groups (mínimo privilegio de red)

| SG | Dirección | Puerto | Origen/Destino | Justificación |
| --- | --- | --- | --- | --- |
| `sg-lambda` | Egress | 6379 | → `sg-redis` | Conexión a la caché |
| `sg-lambda` | Egress | 443 | → `0.0.0.0/0` | Llamadas HTTPS a servicios AWS (S3 por endpoint, CloudWatch) |
| `sg-lambda` | Ingress | — | (ninguno) | La Lambda no recibe conexiones entrantes directas |
| `sg-redis` | Ingress | 6379 | ← `sg-lambda` | Redis solo acepta a la Lambda |
| `sg-redis` | Egress | — | (por defecto) | No requiere salida |

Punto clave: el SG de Redis referencia el **SG de Lambda como origen**, no un CIDR. Nunca se usa `0.0.0.0/0` en el puerto 6379. Esto cumple el requisito explícito del enunciado.

### 2.3 VPC Endpoint para S3
El VPC Endpoint tipo Gateway (`vpc.tf`) se asocia a la route table privada. El tráfico de la Lambda hacia S3 se enruta por el endpoint y **no sale a internet** ni pasa por el NAT. Beneficios: menor superficie de exposición, sin costo de NAT para ese tráfico y cumplimiento de RNF-05.

### 2.4 Egress controlado
El NAT Gateway existe para salida a internet de la Lambda solo si fuera necesaria (por ejemplo dependencias externas futuras). El tráfico a S3 no lo usa. En producción se recomienda un NAT por AZ (documentado como mejora OPT-05).

---

## 3. IAM — mínimo privilegio

### 3.1 Rol de la Lambda
El rol `sre-prueba-lambda-role` (`lambda.tf`) concede exclusivamente:

| Statement | Acciones | Recurso | Por qué |
| --- | --- | --- | --- |
| `Logs` | `logs:CreateLogGroup/Stream`, `logs:PutLogEvents` | Log group de la Lambda | Registrar ejecución y errores |
| `VpcEni` | `ec2:*NetworkInterface`, `ec2:*PrivateIpAddresses` | `*` | AWS exige `*` para que Lambda cree ENIs en la VPC |
| `S3Results` | `s3:PutObject`, `s3:GetObject` | `arn:.../results/*` | Escribir/leer solo bajo el prefijo de resultados |
| `S3List` | `s3:ListBucket` | `arn:...` (bucket) | Listar el bucket |

**Sobre el `*` en VpcEni:** no es una excepción al mínimo privilegio por descuido. AWS no permite acotar por recurso las acciones de gestión de ENI que Lambda necesita para operar dentro de una VPC; es el patrón oficial. Se documenta explícitamente para la entrevista.

### 3.2 Trust policy
Solo el servicio `lambda.amazonaws.com` puede asumir el rol (`sts:AssumeRole`). No hay confianza cruzada con otras cuentas ni usuarios.

---

## 4. Seguridad de datos (S3)

| Control | Configuración | Efecto |
| --- | --- | --- |
| Block Public Access | Las 4 flags en `true` | Imposible exponer el bucket públicamente |
| Versionado | `Enabled` | Protección ante sobrescritura/borrado accidental |
| Bucket policy — allow | Solo el rol de la Lambda | Ningún otro principal opera el bucket |
| Bucket policy — deny | `aws:SecureTransport = false` | Rechaza cualquier acceso sin TLS |
| Cifrado | SSE-S3 (AES256) por defecto | Datos cifrados en reposo |

El acceso efectivo al bucket requiere: ser el rol de la Lambda **y** usar TLS **y** (a nivel de red) pasar por el VPC Endpoint. Defensa en capas.

---

## 5. Gestión de secrets
- No hay credenciales embebidas en el código ni en los archivos `.tf`.
- Las variables de entorno de la Lambda solo contienen endpoints y configuración no sensible (`REDIS_HOST`, `S3_BUCKET`, `CACHE_TTL`).
- Redis se despliega sin autenticación (acceso restringido por red). Si se requiriera `AUTH`, el token se guardaría en **Parameter Store** o **Secrets Manager** y se leería en tiempo de ejecución, nunca en el repositorio (mejora OPT-03).

---

## 6. Validación de seguridad (opcional — gates DevSecOps)
Antes de desplegar se puede pasar el código por escáneres estáticos gratuitos:

```bash
tfsec .          # hallazgos de seguridad en Terraform
checkov -d .     # políticas de cumplimiento IaC
```

Hallazgos esperables y su justificación:
- *"Lambda egress 443 a 0.0.0.0/0"* → necesario para alcanzar servicios AWS; aceptado.
- *"ENI actions sobre `*`"* → requisito de Lambda en VPC; aceptado y documentado.

---

## 7. Checklist de seguridad (para Go Live)
- [ ] Lambda y Redis sin IP pública.
- [ ] SG Redis acepta 6379 solo desde SG Lambda.
- [ ] VPC Endpoint S3 operativo y asociado a la RT privada.
- [ ] S3 con BPA x4, versionado y bucket policy aplicada.
- [ ] Deny no-TLS activo en el bucket.
- [ ] Rol IAM sin permisos `*` salvo ENI (documentado).
- [ ] Sin secrets en el repositorio.
