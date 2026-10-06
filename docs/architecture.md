# Arquitectura

```mermaid
flowchart LR
  subgraph RG["rg-sreagent-netops · Sweden Central"]
    SRE["Azure SRE Agent<br/>Autonomous · RG scope"]
    LAW["Log Analytics"]
    subgraph HUB["vnet-hub-sre-netops-sc · 10.0.0.0/16"]
      AFW["Azure Firewall Standard<br/>10.0.0.4"]
    end
    subgraph SP1["vnet-spoke1-sre-netops-sc · 10.1.0.0/16"]
      VM1["VM spoke1<br/>10.1.1.4:8080"]
      RT1["UDR -> 10.0.0.4"]
      N1["NSG + ASG"]
    end
    subgraph SP2["vnet-spoke2-sre-netops-sc · 10.2.0.0/16"]
      VM2["VM spoke2<br/>10.2.1.4:8080"]
      RT2["UDR -> 10.0.0.4"]
      N2["NSG + ASG"]
    end
    VM1 --> RT1 --> AFW --> RT2 --> VM2
    VM2 --> RT2 --> AFW --> RT1 --> VM1
    AFW --> LAW
    SRE --> LAW
    SRE -. Contributor limitado al RG .-> HUB
    SRE -. Contributor limitado al RG .-> SP1
    SRE -. Contributor limitado al RG .-> SP2
  end
```

## Flujo de tráfico

No existe peering directo entre spokes. Las UDR más específicas de cada subnet envían el prefijo del spoke opuesto a `10.0.0.4`. Azure Firewall permite TCP/8080 en ambos sentidos y registra la decisión en Log Analytics.

Las dos VM sirven una página HTTP y ejecutan una sonda cada minuto. No tienen IP pública. Azure SRE Agent puede inspeccionar configuración, Activity Log, telemetría y, cuando sea necesario, ejecutar diagnósticos sobre las VM dentro del RG.

## Scope del agente

El agente y sus identidades tienen roles únicamente en `rg-sreagent-netops`. Aunque el conector Azure Monitor usa el endpoint de la suscripción, la identidad no dispone de permisos heredados fuera del RG. El modo de acción es `Autonomous` y el nivel de acceso es `High`, necesario para corregir rutas, reglas y asociaciones.

## Naming CAF

Se usan prefijos como `rg`, `vnet`, `snet`, `afw`, `afwp`, `rt`, `nsg`, `asg`, `nic`, `vm`, `pip`, `log`, `appi` e `id`, seguidos de workload, función y región abreviada.
