# Catálogo de fallos de la demo

| ID | Fallo | Evidencia esperada | Baseline a restaurar |
|---|---|---|---|
| `route-blackhole` | La ruta de spoke 1 al spoke 2 cambia a `None` | Error desde `10.1.1.4` hacia `10.2.1.4`; cambio reciente en route table | `VirtualAppliance 10.0.0.4` |
| `nsg-deny` | La regla de spoke 2 cambia de Allow a Deny | Fallo solo hacia spoke 2; deny del NSG | Regla `Allow-HTTP-From-Spoke1` con `Allow` |
| `asg-detach` | La NIC de spoke 2 pierde su ASG | La regla del NSG ya no selecciona el destino | Asociar `asg-app-spoke2-sre-netops-sc` |
| `peering-disable` | El peering spoke 1 a hub pierde acceso a VNet | Ruta no utilizable y peering degradado | `allowVirtualNetworkAccess=true` |
| `firewall-deny` | Se añade una colección Deny prioritaria | `AZFWNetworkRule` muestra Deny | Eliminar `rc-injected-deny` |
| `route-table-detach` | La subnet de spoke 1 pierde la route table | Tráfico puede evitar el firewall o tomar ruta no prevista | Asociar `rt-spoke1-sre-netops-sc` |

