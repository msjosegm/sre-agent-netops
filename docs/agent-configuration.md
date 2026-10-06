# Configuración de Azure SRE Agent

## Componentes

| Elemento | Archivo | Propósito |
|---|---|---|
| Tarea programada | `agent/scheduled-tasks/network-watch.json` | Revisión y remediación cada 30 minutos |
| Response plan | `agent/incident-filters/network-alert-response.json` | Respuesta autónoma a alertas de firewall Sev2 |
| Guardrails | `agent/common-prompts/netops-guardrails.json` | Limitar scope y acciones |
| Subagent | `agent/subagents/network-operator.json` | Especialista de red |
| Skill | `agent/skills/network-triage.json` | Secuencia de troubleshooting |
| Knowledge | `agent/knowledge/*.md` | Baseline, runbook y catálogo de fallos |

El subagent dispone explícitamente de `RunAzCliReadCommands`, `RunAzCliWriteCommands`, `GetAzCliHelp`, `QueryLogAnalyticsByWorkspaceId` y `SearchMemory`. Esto evita que el runtime intente instalar extensiones o ejecute acciones POST mediante el runner de lectura.

## Plataforma de incidentes

La plataforma de incidentes del agente es **Azure Monitor**, configurada declarativamente como `incidentManagementConfiguration.type: AzMonitor`. El conector `azure-monitor-netops` permite al agente consultar las alertas visibles para su identidad.

El scope operativo continúa limitado a `rg-sreagent-netops`: configurar Azure Monitor como plataforma no concede permisos adicionales fuera del resource group.

## Response plan

`network-alert-response` procesa únicamente alertas Sev2 cuyo título contiene `SRE NetOps East-West Firewall Deny`. El incidente se asigna a `network-operator` en modo `Autonomous`, con un máximo de tres intentos de investigación.

El plan ordena correlacionar la alerta con `AZFWNetworkRule`, Activity Log y el baseline antes de actuar. La remediación permitida elimina la desviación confirmada y verifica TCP/8080 en ambos sentidos.

## Network Watcher

Azure mantiene un único Network Watcher por región y suscripción. En esta suscripción, el de Sweden Central es `NetworkWatcherRG/NetworkWatcher_swedencentral`, fuera del RG de la demo.

Las identidades user-assigned y system-assigned del agente reciben `Network Contributor` con scope exacto sobre ese recurso Network Watcher. Esta es la única excepción al scope del RG y permite ejecutar diagnósticos regionales; no concede acceso de modificación a otros recursos alojados en `NetworkWatcherRG`.

## Ciclo automático

1. Revisa cambios de red de los últimos 35 minutos.
2. Valida peering, UDR, NSG, ASG y Firewall Policy.
3. Comprueba conectividad TCP/8080 en ambos sentidos.
4. Correlaciona cambios, configuración y logs.
5. Restaura solo una desviación inequívoca del baseline.
6. Verifica el resultado y registra evidencia en el thread.

## Permisos

Las identidades user-assigned y system-assigned reciben `Reader`, `Log Analytics Reader` y `Contributor` en el RG. No reciben permisos a nivel de suscripción. El usuario que despliega recibe `SRE Agent Administrator` sobre el recurso del agente.

`Contributor` es deliberado para esta demo porque el agente debe corregir recursos de red. En producción conviene sustituirlo por un rol personalizado que incluya únicamente las operaciones necesarias de `Microsoft.Network`.

## Limitaciones de preview

La API usada es `2025-05-01-preview`. Los subagents, skills, prompts, tareas y knowledge se aplican después del ARM deployment mediante data plane. Los Markdown se crean como conectores `KnowledgeFile` para que aparezcan en **Knowledge Sources**. Estos conectores son inmutables en la API actual: el script crea los que faltan y conserva los existentes. Para publicar una revisión, usa un nombre de archivo nuevo.
