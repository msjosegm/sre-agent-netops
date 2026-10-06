# Tool routing para investigaciones de red

## Azure CLI

- Usa `RunAzCliReadCommands` para operaciones `get`, `list`, `show` y `query`.
- Usa `RunAzCliWriteCommands` solo para las operaciones `update` documentadas.
- Ejecuta una sola orden por llamada, sin `&&`, pipes, redirecciones, `--query`, `-o` ni `--output`.
- No uses Network Watcher, VM Run Command, `curl` ni `az rest`.
- Usa las sondas continuas y `AZFWNetworkRule` para la verificación end-to-end.
- Usa `GetAzCliHelp` si no conoces el contrato de un comando.
- No instales extensiones de Azure CLI desde el sandbox.

## Azure Firewall Policy

La extensión preview `azure-firewall` no está disponible en el sandbox del agente. No uses:

```text
az network firewall policy rule-collection-group ...
```

Usa `az resource show/update` con la API `2024-05-01`:

```text
--namespace Microsoft.Network --resource-type ruleCollectionGroups --parent firewallPolicies/afwp-sre-netops-sc --name rcg-netops
```

La restauración permitida conserva únicamente `rc-allow-east-west` con prioridad 200. La colección de fallo `rc-injected-deny`, prioridad 100, puede eliminarse cuando sea la causa confirmada.

## Log Analytics

- Usa `QueryLogAnalyticsByWorkspaceId` sobre `log-sre-netops-sc`.
- No uses `curl`, tokens manuales ni llamadas directas al endpoint REST de Log Analytics.
- La tabla principal para el firewall es `AZFWNetworkRule`.
