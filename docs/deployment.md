# Despliegue de la infraestructura y Azure SRE Agent

Este procedimiento crea todos los recursos en **Sweden Central** dentro del único resource group **`rg-sreagent-netops`**. El despliegue se divide en dos capas:

1. **Control plane de Azure:** resource group, red hub-and-spoke, Azure Firewall, VM, observabilidad, identidades, RBAC, recurso Azure SRE Agent y conectores.
2. **Data plane de Azure SRE Agent:** guardrails, subagent, skill, tarea programada y knowledge sources.

No ejecutes estos comandos hasta revisar el coste de Azure Firewall Standard y los permisos que recibirá el agente.

## 1. Prerrequisitos

- Suscripción habilitada para Azure SRE Agent en Sweden Central.
- Azure CLI, Bicep CLI, `jq` y `curl`.
- Rol `Owner`, o `Contributor` más `User Access Administrator`, para crear el RG y RBAC.
- Cuota suficiente para Azure Firewall Standard y dos VM `Standard_D2as_v5`.
- Proveedor de modelo `MicrosoftFoundry` o `Anthropic` disponible para la suscripción en Sweden Central.
- Una clave pública SSH. Las VM no admiten autenticación mediante contraseña.

Comprueba las herramientas:

```bash
az version
bicep --version
jq --version
curl --version
```

Si no tienes una clave SSH:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "azure-sreagent-netops"
```

## 2. Seleccionar y preparar la suscripción

```bash
az login
az account list --output table

export AZURE_SUBSCRIPTION_ID="<subscription-id>"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show --query '{subscription:name,id:id,tenant:tenantId}' --output table
```

Comprueba que Azure SRE Agent está disponible para la suscripción abriendo [sre.azure.com](https://sre.azure.com), seleccionando **Create agent** y verificando que **Sweden Central** aparece en la lista de regiones.

Registra los proveedores si todavía no están registrados:

```bash
for provider in \
  Microsoft.App \
  Microsoft.Authorization \
  Microsoft.Compute \
  Microsoft.Insights \
  Microsoft.ManagedIdentity \
  Microsoft.Network \
  Microsoft.OperationalInsights; do
  az provider register --namespace "$provider"
done

az provider show \
  --namespace Microsoft.App \
  --query registrationState \
  --output tsv
```

El registro puede tardar varios minutos. Antes de desplegar, `Microsoft.App` debe devolver `Registered`.

## 3. Configurar parámetros

La región y el resource group están fijados en la plantilla:

| Parámetro | Valor |
|---|---|
| Región | `swedencentral` |
| Resource group | `rg-sreagent-netops` |
| Agente | `sre-netops-demo-sc` |
| Tamaño de VM | `Standard_D2as_v5` |
| Proveedor por defecto | `MicrosoftFoundry` |

Exporta la clave SSH:

```bash
export ADMIN_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
```

Si la suscripción ofrece Anthropic en lugar de Microsoft Foundry:

```bash
export SRE_MODEL_PROVIDER="Anthropic"
```

En caso contrario, omite la variable o usa:

```bash
export SRE_MODEL_PROVIDER="MicrosoftFoundry"
```

El tamaño predeterminado de las dos VM es `Standard_D2as_v5`, que se ha comprobado sin restricciones para Sweden Central. La disponibilidad de capacidad puede cambiar por suscripción y momento. Para seleccionar otro SKU:

```bash
az vm list-skus \
  --location swedencentral \
  --resource-type virtualMachines \
  --all \
  --query "[?length(restrictions)==\`0\`].name" \
  --output tsv

export VM_SIZE="Standard_D2s_v5"
```

## 4. Validar las plantillas sin desplegar

La validación local compila Bicep, valida los JSON del agente y comprueba la sintaxis de los scripts:

```bash
./scripts/validate.sh
```

Opcionalmente, revisa los cambios que Azure realizaría sin aplicarlos:

```bash
az deployment sub what-if \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters \
    adminSshPublicKey="$ADMIN_SSH_PUBLIC_KEY" \
    vmSize="${VM_SIZE:-Standard_D2as_v5}" \
    sreModelProvider="${SRE_MODEL_PROVIDER:-MicrosoftFoundry}"
```

## 5. Despliegue completo automatizado

El método recomendado despliega primero los recursos ARM y después configura el data plane de Azure SRE Agent:

```bash
./scripts/deploy.sh
```

El script:

1. Crea `rg-sreagent-netops` en `swedencentral`.
2. Despliega red, firewall, VM y observabilidad.
3. Crea las identidades y el Azure SRE Agent.
4. Asigna `Reader`, `Log Analytics Reader` y `Contributor` únicamente sobre `rg-sreagent-netops`.
5. Descubre el Network Watcher de Sweden Central y concede `Network Contributor` con scope exclusivo sobre ese recurso.
6. Establece Azure Monitor como plataforma de incidentes y configura los conectores de Azure Monitor y Log Analytics.
7. Crea una alerta Sev2 por tráfico east-west denegado y configura el response plan de Azure Monitor.
8. Configura subagent, skill, guardrails y la tarea `*/30 * * * *`.
9. Crea los Markdown de `agent/knowledge` como conectores `KnowledgeFile` visibles en Knowledge Sources.

El despliegue de Azure Firewall puede tardar varios minutos. No interrumpas el proceso.

## 6. Despliegue por fases

Este método es útil para revisar la infraestructura antes de configurar las extensiones del agente.

### Fase 1: infraestructura y recurso base del agente

```bash
./scripts/deploy.sh --skip-agent-config
```

Confirma que el deployment terminó correctamente:

```bash
az deployment sub list \
  --query "[?starts_with(name, 'sreagent-netops-')].{name:name,state:properties.provisioningState,timestamp:properties.timestamp}" \
  --output table

az resource list \
  --resource-group rg-sreagent-netops \
  --query "[].{name:name,type:type,location:location}" \
  --output table
```

### Fase 2: autenticación del data plane

El data plane del agente usa la audiencia `https://azuresre.dev`, diferente del token ARM normal:

```bash
az login --scope "https://azuresre.dev/.default"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

az account get-access-token \
  --resource https://azuresre.dev \
  --query expiresOn \
  --output tsv
```

### Fase 3: configuración del agente

```bash
./scripts/configure-agent.sh
```

Este script es idempotente para los elementos configurados mediante `PUT`. Los knowledge files se vuelven a cargar; revisa posibles documentos duplicados si lo ejecutas repetidamente tras cambiar nombres.

## 7. Verificar la infraestructura

Comprueba que todos los recursos están en el RG requerido:

```bash
az resource list \
  --resource-group rg-sreagent-netops \
  --query "[].{name:name,type:type,location:location}" \
  --output table
```

Comprueba la topología y el baseline:

```bash
./scripts/demo-failures.sh status
```

Comprueba el estado del agente:

```bash
az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-sreagent-netops/providers/Microsoft.App/agents/sre-netops-demo-sc?api-version=2025-05-01-preview" \
  --query '{state:properties.provisioningState,power:properties.powerState,endpoint:properties.agentEndpoint,managedResources:properties.knowledgeGraphConfiguration.managedResources}' \
  --output json
```

El único elemento de `managedResources` debe ser:

```text
/subscriptions/<subscription-id>/resourceGroups/rg-sreagent-netops
```

Comprueba que las identidades no tienen asignaciones fuera del RG:

```bash
AGENT_IDENTITY_PRINCIPAL_ID="$(
  az identity show \
    --resource-group rg-sreagent-netops \
    --name id-sre-netops-demo-sc \
    --query principalId \
    --output tsv
)"

az role assignment list \
  --assignee "$AGENT_IDENTITY_PRINCIPAL_ID" \
  --all \
  --query "[].{role:roleDefinitionName,scope:scope}" \
  --output table
```

## 8. Verificar la configuración de Azure SRE Agent

Abre:

```text
https://sre.azure.com
```

Selecciona `sre-netops-demo-sc` y comprueba:

- **Azure Resources:** solo `rg-sreagent-netops`.
- **Logs:** workspace `log-sre-netops-sc`.
- **Incidents:** plataforma `Azure Monitor`.
- **Response Plans:** `network-alert-response`, Sev2, modo `Autonomous`.
- **Scheduled Tasks:** `network-connectivity-and-drift-watch`.
- **Schedule:** `*/30 * * * *`, equivalente a cada 30 minutos en UTC.
- **Autonomy:** `Autonomous`.
- **Knowledge:** `architecture-baseline.md`, `troubleshooting-runbook.md` y `demo-scenarios.md`.
- **Builder/Agent Canvas:** subagent `network-operator` y skill `network-triage`.

Comprueba el acceso al Network Watcher regional:

```bash
NW_ID="$(
  az network watcher list \
    --query "[?location=='swedencentral'].id | [0]" \
    --output tsv
)"

for PRINCIPAL_ID in \
  "$(az identity show -g rg-sreagent-netops -n id-sre-netops-demo-sc --query principalId -o tsv)" \
  "$(az rest -m GET \
      --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-sreagent-netops/providers/Microsoft.App/agents/sre-netops-demo-sc?api-version=2025-05-01-preview" \
      --query identity.principalId -o tsv)"; do
  az role assignment list \
    --assignee "$PRINCIPAL_ID" \
    --scope "$NW_ID" \
    --query "[].{role:roleDefinitionName,scope:scope}" \
    --output table
done
```

Ambas identidades deben mostrar `Network Contributor` con scope exacto sobre `NetworkWatcher_swedencentral`.

Comprueba la alerta:

```bash
az monitor scheduled-query show \
  --resource-group rg-sreagent-netops \
  --name alert-sre-netops-east-west-deny \
  --query '{name:name,displayName:displayName,severity:severity,enabled:enabled}' \
  --output table
```

Ejecuta manualmente la tarea programada una primera vez. El resultado inicial debe indicar que:

- Los cuatro peerings están conectados.
- Las UDR apuntan a `10.0.0.4`.
- Los NSG permiten TCP/8080 entre spokes.
- Las NIC están asociadas a sus ASG.
- La Firewall Policy permite el tráfico en ambos sentidos.

## 9. Problemas habituales

### No se obtiene un token para `azuresre.dev`

```bash
az logout
az login --scope "https://azuresre.dev/.default"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
./scripts/configure-agent.sh
```

### El proveedor de modelo no está disponible

Comprueba los proveedores disponibles en el asistente de creación de [sre.azure.com](https://sre.azure.com). Después selecciona el correcto:

```bash
export SRE_MODEL_PROVIDER="Anthropic"
./scripts/deploy.sh
```

Si el recurso base ya existe, el despliegue actualiza su configuración.

### El SKU de VM no tiene capacidad en Sweden Central

Consulta los tamaños sin restricciones y selecciona uno antes de reintentar:

```bash
az vm list-skus \
  --location swedencentral \
  --resource-type virtualMachines \
  --all \
  --query "[?length(restrictions)==\`0\` && capabilities[?name=='vCPUs' && to_number(value)>=\`2\`]].name" \
  --output tsv

export VM_SIZE="Standard_D2as_v5"
./scripts/deploy.sh
```

No es necesario eliminar el resource group después de un deployment fallido. Corrige el SKU y vuelve a ejecutar el script; ARM conservará los recursos completados y continuará de forma declarativa.

### Error de autorización al crear role assignments

Activa mediante PIM el rol `Owner` o `User Access Administrator` en la suscripción y vuelve a ejecutar el deployment. Tener solo `Contributor` no permite crear asignaciones RBAC.

### El agente existe, pero faltan knowledge sources o la tarea

La infraestructura ARM terminó, pero falló la fase de data plane. Renueva el token y ejecuta únicamente:

```bash
az login --scope "https://azuresre.dev/.default"
./scripts/configure-agent.sh
```

### Un deployment parcial necesita reanudarse

```bash
./scripts/deploy.sh
```

Las plantillas y scripts son declarativos; volver a ejecutarlos actualiza los recursos existentes sin crear otro resource group.

### `ZonalAzureFirewallCannotReferenceNoZonePublicIp`

Este error aparece cuando Azure Firewall declara zonas de disponibilidad, pero la IP pública existente no tiene zonas. La demo usa ahora un firewall regional sin la propiedad `zones`, compatible con la IP pública regional creada durante el intento anterior.

No elimines la IP pública ni el resource group. Actualiza el repositorio y vuelve a ejecutar:

```bash
./scripts/deploy.sh
```

### `InvalidActionMode: Invalid action mode 'Automatic'`

La versión actual de la API `Microsoft.App/agents@2025-05-01-preview` acepta `Review` o `Autonomous`. La plantilla y la tarea programada usan ahora `Autonomous`.

Vuelve a ejecutar el deployment completo:

```bash
./scripts/deploy.sh
```

Si la infraestructura termina correctamente pero falla únicamente la configuración del data plane:

```bash
az login --scope "https://azuresre.dev/.default"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
./scripts/configure-agent.sh
```

## 10. Limpieza

Azure Firewall genera coste mientras permanece desplegado. Al finalizar la demo elimina el RG completo:

```bash
az group delete --name rg-sreagent-netops --yes --no-wait
```

Comprueba posteriormente que el RG ya no existe:

```bash
az group exists --name rg-sreagent-netops
```

El resultado esperado es `false`.
