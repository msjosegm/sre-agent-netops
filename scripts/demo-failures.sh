#!/usr/bin/env bash
set -euo pipefail

SCENARIO="${1:-list}"
ACTION="${2:-inject}"

show_list() {
  cat <<'EOF'
Uso: ./scripts/demo-failures.sh <escenario> [inject|restore]

Escenarios:
  route-blackhole    Convierte la ruta de spoke1 a spoke2 en blackhole.
  nsg-deny           Cambia a Deny la regla TCP/8080 de spoke2.
  asg-detach         Desasocia el ASG de la NIC de spoke2.
  peering-disable    Deshabilita acceso en el peering spoke1 -> hub.
  firewall-deny      Añade una regla Deny prioritaria en Azure Firewall.
  route-table-detach Desasocia la route table de la subnet de spoke1.
  status             Muestra la configuración relevante.
  restore-all        Reaplica el baseline Bicep (requiere ADMIN_SSH_PUBLIC_KEY).
EOF
}

if [[ "$SCENARIO" == "list" ]]; then
  show_list
  exit 0
fi

RG="${RESOURCE_GROUP_NAME:-rg-sreagent-netops}"
SUB="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || true)}"
SUFFIX="sre-netops-sc"

[[ -n "$SUB" ]] || { echo "Define AZURE_SUBSCRIPTION_ID o inicia sesión con az login." >&2; exit 1; }
az account set --subscription "$SUB"

RT1="rt-spoke1-${SUFFIX}"
NSG2="nsg-app-spoke2-${SUFFIX}"
VNET1="vnet-spoke1-${SUFFIX}"
NIC2="nic-vm-spoke2-${SUFFIX}"
ASG2="asg-app-spoke2-${SUFFIX}"
AFWP="afwp-${SUFFIX}"
ALERT_RULE="alert-sre-netops-east-west-deny"

require_scope() {
  local actual
  actual="$(az group show --name "$RG" --query name -o tsv 2>/dev/null || true)"
  [[ "$actual" == "rg-sreagent-netops" ]] || {
    echo "Por seguridad, este script solo opera sobre rg-sreagent-netops." >&2
    exit 1
  }
}

active_firewall_alert_id() {
  az rest --method GET \
    --url "https://management.azure.com/subscriptions/${SUB}/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&targetResourceGroup=${RG}" \
    --query "value[?properties.essentials.monitorCondition=='Fired' && properties.essentials.alertState!='Closed' && contains(properties.essentials.alertRule, '${ALERT_RULE}')].id | [0]" \
    -o tsv
}

status() {
  echo "== Ruta spoke1 -> spoke2 =="
  az network route-table route show -g "$RG" --route-table-name "$RT1" \
    -n route-to-spoke2-via-firewall --query '{prefix:addressPrefix,nextHop:nextHopType,nextHopIp:nextHopIpAddress}' -o table
  echo "== NSG spoke2 =="
  az network nsg rule show -g "$RG" --nsg-name "$NSG2" -n Allow-HTTP-From-Spoke1 \
    --query '{access:access,priority:priority,port:destinationPortRange}' -o table
  echo "== Peering spoke1 -> hub =="
  az network vnet peering show -g "$RG" --vnet-name "$VNET1" -n peer-spoke1-to-hub \
    --query '{state:peeringState,vnetAccess:allowVirtualNetworkAccess,forwarded:allowForwardedTraffic}' -o table
  echo "== ASG de NIC spoke2 =="
  az network nic ip-config show -g "$RG" --nic-name "$NIC2" -n ipconfig1 \
    --query 'applicationSecurityGroups[].id' -o tsv
  echo "== Route table de subnet spoke1 =="
  az network vnet subnet show -g "$RG" --vnet-name "$VNET1" -n snet-app-spoke1 \
    --query 'routeTable.id' -o tsv
  echo "== Alerta activa de Azure Firewall =="
  active_firewall_alert_id
}

require_scope

case "$SCENARIO:$ACTION" in
  status:inject)
    status
    ;;
  restore-all:inject)
    [[ -n "${ADMIN_SSH_PUBLIC_KEY:-}" ]] || { echo "Define ADMIN_SSH_PUBLIC_KEY." >&2; exit 1; }
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy.sh" --skip-agent-config
    ;;
  route-blackhole:inject)
    az network route-table route update -g "$RG" --route-table-name "$RT1" \
      -n route-to-spoke2-via-firewall --next-hop-type None --remove nextHopIpAddress -o none
    echo "Fallo inyectado: spoke1 ya no puede alcanzar spoke2."
    ;;
  route-blackhole:restore)
    az network route-table route update -g "$RG" --route-table-name "$RT1" \
      -n route-to-spoke2-via-firewall --next-hop-type VirtualAppliance --next-hop-ip-address 10.0.0.4 -o none
    echo "Ruta restaurada."
    ;;
  nsg-deny:inject)
    az network nsg rule update -g "$RG" --nsg-name "$NSG2" \
      -n Allow-HTTP-From-Spoke1 --access Deny -o none
    echo "Fallo inyectado: NSG de spoke2 deniega TCP/8080."
    ;;
  nsg-deny:restore)
    az network nsg rule update -g "$RG" --nsg-name "$NSG2" \
      -n Allow-HTTP-From-Spoke1 --access Allow -o none
    echo "Regla NSG restaurada."
    ;;
  asg-detach:inject)
    az network nic ip-config update -g "$RG" --nic-name "$NIC2" -n ipconfig1 \
      --remove applicationSecurityGroups -o none
    echo "Fallo inyectado: NIC de spoke2 sin ASG."
    ;;
  asg-detach:restore)
    az network nic ip-config update -g "$RG" --nic-name "$NIC2" -n ipconfig1 \
      --application-security-groups "$ASG2" -o none
    echo "ASG restaurado."
    ;;
  peering-disable:inject)
    az network vnet peering update -g "$RG" --vnet-name "$VNET1" \
      -n peer-spoke1-to-hub --set allowVirtualNetworkAccess=false -o none
    echo "Fallo inyectado: peering spoke1 -> hub sin acceso de VNet."
    ;;
  peering-disable:restore)
    az network vnet peering update -g "$RG" --vnet-name "$VNET1" \
      -n peer-spoke1-to-hub --set allowVirtualNetworkAccess=true allowForwardedTraffic=true -o none
    echo "Peering restaurado."
    ;;
  firewall-deny:inject)
    existing_collection="$(az network firewall policy rule-collection-group show \
      -g "$RG" --policy-name "$AFWP" -n rcg-netops \
      --query "ruleCollections[?name=='rc-injected-deny'].name | [0]" -o tsv)"
    if [[ -n "$existing_collection" ]]; then
      echo "El fallo ya estaba inyectado: rc-injected-deny existe."
    else
      active_alert="$(active_firewall_alert_id)"
      if [[ -n "$active_alert" ]]; then
        echo "No se inyecta el fallo: la alerta anterior sigue Fired y Azure Monitor reutilizaría la misma instancia." >&2
        echo "Espera a que monitorCondition sea Resolved antes de repetir la demo." >&2
        exit 1
      fi
      az network firewall policy rule-collection-group collection add-filter-collection \
        -g "$RG" --policy-name "$AFWP" --rule-collection-group-name rcg-netops \
        --name rc-injected-deny --collection-priority 100 --action Deny \
        --rule-name Deny-Spoke1-To-Spoke2 --rule-type NetworkRule \
        --source-addresses 10.1.0.0/16 --destination-addresses 10.2.0.0/16 \
        --destination-ports 8080 --ip-protocols TCP --only-show-errors -o none
      echo "Fallo inyectado: Azure Firewall deniega spoke1 -> spoke2."
    fi
    ;;
  firewall-deny:restore)
    existing_collection="$(az network firewall policy rule-collection-group show \
      -g "$RG" --policy-name "$AFWP" -n rcg-netops \
      --query "ruleCollections[?name=='rc-injected-deny'].name | [0]" -o tsv)"
    if [[ -z "$existing_collection" ]]; then
      echo "Baseline ya restaurado: rc-injected-deny no existe."
    else
      az network firewall policy rule-collection-group collection remove \
        -g "$RG" --policy-name "$AFWP" --rule-collection-group-name rcg-netops \
        --name rc-injected-deny --only-show-errors -o none
      echo "Colección Deny eliminada."
    fi
    ;;
  route-table-detach:inject)
    az network vnet subnet update -g "$RG" --vnet-name "$VNET1" \
      -n snet-app-spoke1 --remove routeTable -o none
    echo "Fallo inyectado: subnet de spoke1 sin route table."
    ;;
  route-table-detach:restore)
    az network vnet subnet update -g "$RG" --vnet-name "$VNET1" \
      -n snet-app-spoke1 --route-table "$RT1" -o none
    echo "Route table restaurada."
    ;;
  *)
    show_list
    exit 1
    ;;
esac
