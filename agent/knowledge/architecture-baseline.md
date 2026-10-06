# Baseline de red de la demo

## Scope

- Suscripción: la seleccionada al desplegar.
- Único resource group autorizado: `rg-sreagent-netops`.
- Región de todos los recursos: `swedencentral`.

## Topología y direccionamiento

| Elemento | Nombre | Prefijo/IP |
|---|---|---|
| Hub VNet | `vnet-hub-sre-netops-sc` | `10.0.0.0/16` |
| Azure Firewall | `afw-sre-netops-sc` | `10.0.0.4` |
| Spoke 1 VNet | `vnet-spoke1-sre-netops-sc` | `10.1.0.0/16` |
| Spoke 1 subnet | `snet-app-spoke1` | `10.1.1.0/24` |
| Spoke 1 VM | `vm-app-spoke1-sre-netops-sc` | `10.1.1.4` |
| Spoke 2 VNet | `vnet-spoke2-sre-netops-sc` | `10.2.0.0/16` |
| Spoke 2 subnet | `snet-app-spoke2` | `10.2.1.0/24` |
| Spoke 2 VM | `vm-app-spoke2-sre-netops-sc` | `10.2.1.4` |

## Invariantes

1. Cada spoke tiene peering bidireccional con el hub.
2. Los cuatro peerings tienen `allowVirtualNetworkAccess=true` y `allowForwardedTraffic=true`.
3. No existe peering directo entre spokes.
4. `rt-spoke1-sre-netops-sc` enruta `10.2.0.0/16` a `VirtualAppliance 10.0.0.4`.
5. `rt-spoke2-sre-netops-sc` enruta `10.1.0.0/16` a `VirtualAppliance 10.0.0.4`.
6. Cada subnet conserva asociada su route table y su NSG.
7. Cada NIC pertenece al ASG de su spoke.
8. Los NSG permiten TCP/8080 desde el prefijo del spoke opuesto hacia el ASG local.
9. `afwp-sre-netops-sc/rcg-netops/rc-allow-east-west` tiene prioridad 200 y permite TCP/8080 en ambos sentidos. La prioridad 100 queda reservada para `rc-injected-deny` durante la demo.
10. Las dos VM sirven HTTP en el puerto 8080 y ejecutan una sonda cada minuto.

## Remediaciones permitidas

El agente puede restaurar cualquiera de los valores anteriores si existe evidencia clara de deriva. No puede borrar recursos, cambiar RBAC, añadir exposición pública ni actuar fuera del resource group.
