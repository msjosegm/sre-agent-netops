# Azure SRE Agent - NetOps demo

Demo reproducible de operaciones de red con Azure SRE Agent, desplegada por completo en **Sweden Central** y contenida en el resource group **`rg-sreagent-netops`**.

La solución crea un hub-and-spoke con dos spokes, Azure Firewall, rutas definidas por el usuario, NSG, ASG, dos VM sin IP pública que generan tráfico HTTP entre spokes, Log Analytics y un Azure SRE Agent con Azure Monitor como plataforma de incidentes y permisos de actuación limitados al resource group de la demo.

## Contenido

```text
.
├── agent/                  # Knowledge, response plan, subagent, skill, guardrails y tarea
├── docs/                   # Arquitectura, despliegue, operación y guion de demo
├── infra/                  # Bicep a nivel de suscripción y módulos
└── scripts/                # Despliegue, configuración, validación y fallos
```

## Inicio rápido

No se ha desplegado ningún recurso. Para preparar y revisar la demo:

```bash
./scripts/validate.sh
```

Para desplegarla deliberadamente:

```bash
az login
export AZURE_SUBSCRIPTION_ID="<subscription-id>"
export ADMIN_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
./scripts/deploy.sh
```

Las VM usan `Standard_D2as_v5` por defecto. Puedes elegir otro tamaño disponible con `export VM_SIZE="<sku>"`.

La [guía de despliegue](docs/deployment.md) contiene el procedimiento completo para registrar proveedores, seleccionar el modelo, ejecutar un `what-if`, desplegar la infraestructura, autenticar el data plane, cargar la configuración del agente y verificar RBAC y knowledge sources.

Después, usa `./scripts/demo-failures.sh list` para ver los escenarios y consulta [docs/demo-guide.md](docs/demo-guide.md) para ejecutar la demostración.

Para validar todos los escenarios sobre un entorno desplegado:

```bash
./scripts/test-demo-scenarios.sh
```

## Decisiones de seguridad

- El agente recibe `Contributor`, `Reader` y `Log Analytics Reader` solamente en `rg-sreagent-netops`.
- No hay asignaciones a nivel de suscripción.
- Como excepción diagnóstica, ambas identidades reciben `Network Contributor` exclusivamente sobre el recurso regional `NetworkWatcher_swedencentral`, que Azure puede alojar en `NetworkWatcherRG`.
- Azure Monitor genera una alerta Sev2 cuando Azure Firewall deniega tráfico TCP/8080 entre spokes; el response plan la entrega a `network-operator`.
- Las VM no tienen IP pública ni aceptan contraseñas.
- El agente opera en modo `Autonomous`, pero sus guardrails prohíben borrar recursos y salir del RG.
- Todos los nombres siguen las abreviaturas recomendadas por Azure CAF.
- Azure Firewall Standard es el principal componente de coste; destruye la demo al terminar.

## Referencias

- [Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/)
- [Regiones soportadas](https://learn.microsoft.com/azure/sre-agent/supported-regions)
- [Tareas programadas](https://learn.microsoft.com/azure/sre-agent/create-scheduled-task)
- [API de Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/api-reference)
- [Abreviaturas CAF](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
