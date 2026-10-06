# Guion de la demo

## Preparación

1. Confirma el baseline con `./scripts/demo-failures.sh status`.
2. En Azure SRE Agent abre la tarea `network-connectivity-and-drift-watch`.
3. Ejecuta manualmente la tarea para obtener un thread sano inicial.
4. Elige un escenario y ejecuta `inject`.
5. Espera la siguiente ejecución o lanza la tarea manualmente.
6. Explica cómo el agente reúne evidencia, encuentra el cambio y restaura el baseline.
7. Comprueba el estado y, si hace falta, ejecuta `restore`.

## Escenarios

| Escenario | Inyección | Qué debe detectar y resolver |
|---|---|---|
| Ruta blackhole | `./scripts/demo-failures.sh route-blackhole inject` | La UDR cambió a `None`; restaurar `VirtualAppliance 10.0.0.4` |
| NSG deny | `./scripts/demo-failures.sh nsg-deny inject` | Regla TCP/8080 cambió a Deny; restaurar Allow |
| ASG desasociado | `./scripts/demo-failures.sh asg-detach inject` | La NIC dejó de pertenecer al ASG; volver a asociarlo |
| Peering deshabilitado | `./scripts/demo-failures.sh peering-disable inject` | `allowVirtualNetworkAccess=false`; restaurar el peering |
| Firewall deny | `./scripts/demo-failures.sh firewall-deny inject` | Colección Deny con prioridad 100 por delante del Allow 200; eliminar solo `rc-injected-deny` |
| Route table desasociada | `./scripts/demo-failures.sh route-table-detach inject` | La subnet perdió su UDR; volver a asociar la tabla |

Cada escenario admite `restore`, por ejemplo:

```bash
./scripts/demo-failures.sh nsg-deny restore
```

## Demostración de alerta y response plan

El escenario `firewall-deny` está conectado a Azure Monitor:

```bash
./scripts/demo-failures.sh firewall-deny inject
```

Las sondas de las VM generan tráfico cada minuto. Azure Firewall lo deniega y escribe en `AZFWNetworkRule`. La regla `SRE NetOps East-West Firewall Deny` evalúa cada minuto con una ventana de cinco minutos y abre una alerta Sev2. El response plan `network-alert-response` entrega el incidente a `network-operator`, que debe:

1. Confirmar los eventos Deny.
2. Correlacionarlos con la creación de `rc-injected-deny`.
3. Eliminar únicamente esa colección inyectada.
4. Verificar TCP/8080 en ambos sentidos.
5. Registrar causa raíz, cambio y evidencia.

La primera alerta puede tardar varios minutos debido a la ingestión. Después de restaurar el firewall, el último evento Deny debe salir de la ventana de cinco minutos y la regla debe completar una evaluación sana; normalmente la alerta se resuelve en unos seis minutos.

Azure Monitor usa alertas stateful. No repitas `firewall-deny inject` mientras `monitorCondition` continúe en `Fired`, porque el nuevo fallo se incorporará a la misma instancia y no se generará otro incidente. El script bloquea esta situación. Para observar el estado:

```bash
az monitor scheduled-query show \
  -g rg-sreagent-netops \
  -n alert-sre-netops-east-west-deny \
  -o table

az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&targetResourceGroup=rg-sreagent-netops" \
  --query "value[?contains(properties.essentials.alertRule, 'alert-sre-netops-east-west-deny')].properties.essentials" \
  --output table
```

Antes de una nueva prueba, confirma que la instancia anterior muestra `monitorCondition=Resolved`.
Las instancias históricas cerradas manualmente pueden conservar `monitorCondition=Fired`; comprueba también que `alertState=Closed`. El script ignora esas instancias cerradas.

Para volver al estado declarativo completo:

```bash
export ADMIN_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
./scripts/demo-failures.sh restore-all
```

## Prueba automatizada de todos los escenarios

Para inyectar, validar y restaurar secuencialmente los seis fallos:

```bash
./scripts/test-demo-scenarios.sh
```

La prueba puede tardar más de diez minutos porque Azure Firewall necesita varios minutos para añadir y retirar una colección. Un `trap` intenta restaurar todos los escenarios si la prueba se interrumpe o falla.

## Narrativa recomendada

Muestra primero el síntoma, después el cambio en Activity Log, la configuración efectiva, los logs de Azure Firewall y finalmente la remediación. El valor de la demo no es solo reparar: es demostrar que el agente limita el blast radius al RG, explica la causa raíz y verifica el servicio.
