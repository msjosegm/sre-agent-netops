# Timeout del runner durante cambios de Azure Firewall

Las actualizaciones del rule collection group de Azure Firewall son operaciones ARM de larga duración. El runner del SRE Agent puede terminar el comando con exit code `124` antes de que Azure complete la operación.

`124` significa timeout local, no rechazo del cambio. No repitas inmediatamente `az resource update`.

Consulta el recurso en una llamada nueva:

```text
az resource show -g rg-sreagent-netops --namespace Microsoft.Network --resource-type ruleCollectionGroups --parent firewallPolicies/afwp-sre-netops-sc --name rcg-netops --api-version 2024-05-01
```

La restauración terminó correctamente si:

- `properties.provisioningState` es `Succeeded`.
- `properties.ruleCollections` contiene únicamente `rc-allow-east-west`.
- `rc-injected-deny` ya no existe.

Si el estado todavía es `Updating`, vuelve a consultar posteriormente. Solo informa de fallo real si ARM devuelve `Failed` o la colección Deny continúa presente después de finalizar el aprovisionamiento.
