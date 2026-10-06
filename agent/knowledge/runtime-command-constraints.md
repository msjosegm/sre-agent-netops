# Restricciones vigentes del runtime del agente

Este documento sustituye cualquier instrucción anterior que recomiende Network Watcher, VM Run Command, `curl`, `az rest` o la extensión `azure-firewall`.

## Reglas obligatorias

- Ejecuta una sola orden Azure CLI por llamada.
- No uses `&&`, pipes, redirecciones, `--query`, `-o` ni `--output`.
- Lecturas: solo verbos `show`, `list`, `get` y `query` con `RunAzCliReadCommands`.
- Cambios: solo los comandos `update` del runbook con `RunAzCliWriteCommands`.
- No instales extensiones.
- No uses `az network watcher test-ip-flow`, VM Run Command, `curl` ni `az rest`.
- Usa `QueryLogAnalyticsByWorkspaceId` para toda consulta KQL.

## Azure Firewall Policy

Lectura compatible:

```text
az resource show -g rg-sreagent-netops --namespace Microsoft.Network --resource-type ruleCollectionGroups --parent firewallPolicies/afwp-sre-netops-sc --name rcg-netops --api-version 2024-05-01
```

La restauración compatible usa `az resource update` con los mismos identificadores y sustituye `properties.ruleCollections` por la colección baseline `rc-allow-east-west`. El comando exacto está en la skill `network-triage`.

## Verificación end-to-end

Las VM `10.1.1.4` y `10.2.1.4` generan una sonda TCP/8080 cada minuto. Consulta `AZFWNetworkRule`, resume el evento más reciente por dirección y confirma `Action=Allow`. No ejecutes comandos dentro de las VM.
