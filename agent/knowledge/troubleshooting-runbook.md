# Runbook de troubleshooting NetOps

## Orden de investigación

1. Identifica hora, origen, destino, protocolo y puerto.
2. Revisa cambios de `Microsoft.Network/*` en los últimos 35 minutos.
3. Comprueba estado y configuración de los peerings.
4. Comprueba asociación y contenido de las route tables.
5. Comprueba reglas NSG y asociaciones ASG de las NIC.
6. Comprueba Azure Firewall Policy y `rcg-netops`.
7. Consulta logs `AZFWNetworkRule` en Log Analytics.
8. Aplica la corrección mínima para volver al baseline.
9. Verifica el recurso y confirma el último resultado de las sondas en ambos sentidos.
10. Documenta la evidencia.

## Reglas de herramientas del agente

- Consulta KQL con `QueryLogAnalyticsByWorkspaceId`; no uses `curl` ni tokens manuales contra Log Analytics.
- Ejecuta una sola orden Azure CLI por llamada, sin `&&`, pipes, redirecciones, `--query`, `-o` ni `--output`.
- No uses Network Watcher, VM Run Command, `az rest` ni extensiones de Azure CLI.
- Consulta y restaura el firewall con `az resource show/update`, API `2024-05-01`, según `runtime-command-constraints.md`.

## Consultas KQL útiles

```kusto
AZFWNetworkRule
| where TimeGenerated > ago(35m)
| where SourceIp startswith "10.1." or SourceIp startswith "10.2."
| project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Action, Rule
| order by TimeGenerated desc
```

```kusto
AzureActivity
| where TimeGenerated > ago(35m)
| where ResourceGroup =~ "rg-sreagent-netops"
| where ResourceProviderValue =~ "MICROSOFT.NETWORK"
| project TimeGenerated, OperationNameValue, ActivityStatusValue, Caller, ResourceId
| order by TimeGenerated desc
```

La consulta `AzureActivity` solo devuelve datos si la suscripción ya exporta Activity Log al workspace. En caso contrario, consulta Activity Log mediante Azure Resource Manager, siempre filtrando `rg-sreagent-netops`.

## Criterios de éxito

- Los últimos eventos de las sondas continuas en `AZFWNetworkRule` muestran `Allow` en ambos sentidos.
- No se modifica ningún recurso fuera del resource group.
