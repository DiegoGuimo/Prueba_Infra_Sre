# 05 — Runbook de Rollback / Limpieza

> Procedimiento para revertir el despliegue y limpiar los recursos. Aplica a LocalStack y a AWS real.

---

## 1. Destruir el stack (Terraform)

### LocalStack
```powershell
cd terraform
tflocal destroy -auto-approve
```

### AWS real
```powershell
cd terraform
terraform destroy -auto-approve
```

> `destroy` elimina todos los recursos gestionados por Terraform (VPC, subnets, NAT, API Gateway, Lambda, S3, IAM, etc.). En AWS real esto detiene el costo de NAT Gateway y ElastiCache.

---

## 2. Limpiar el Redis de Docker (solo LocalStack)

```powershell
docker stop redis-sre
docker rm redis-sre
```

---

## 3. Detener LocalStack

```powershell
localstack stop
```

> LocalStack no persiste estado por defecto: al detenerlo se pierde toda la infraestructura simulada. Esto es esperado en el entorno de validación.

---

## 4. Rollback parcial (revertir un cambio concreto)

Si un `apply` introdujo un cambio no deseado y se quiere volver al estado anterior:

1. Revertir el cambio en el código (`git revert` o editar el `.tf`).
2. Re-aplicar:
   ```powershell
   tflocal apply -auto-approve
   ```
   Terraform calcula el diff y ajusta solo lo necesario.

> Para rollback de código se recomienda trabajar con commits pequeños, de modo que `git revert <commit>` + `apply` restaure un estado conocido.

---

## 5. Escenarios de recuperación

| Escenario | Acción |
| --- | --- |
| LocalStack se reinició y se perdió la infra | `localstack start -d` + `tflocal apply` (recrea todo) |
| El estado de Terraform quedó inconsistente | `tflocal refresh` para resincronizar; en último caso, `destroy` + `apply` |
| Redis perdió los datos | Es caché con TTL: no hay dato que recuperar; se repuebla solo con los MISS |
| Objeto erróneo en S3 | El bucket tiene versionado: se puede restaurar una versión anterior |

---

## 6. Verificar que la limpieza fue completa

### LocalStack
```powershell
docker ps -a --filter "name=redis-sre"   # no debe listar el contenedor
localstack status                          # runtime status: stopped
```

### AWS real
```powershell
terraform state list    # debe salir vacío tras destroy
aws elasticache describe-cache-clusters   # no debe quedar el cluster
aws ec2 describe-nat-gateways             # el NAT debe estar deleted
```

> Confirmar la ausencia del NAT Gateway y de ElastiCache es clave en AWS real para asegurar que no sigue generando costo.
