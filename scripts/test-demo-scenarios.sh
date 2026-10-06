#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO="$ROOT_DIR/scripts/demo-failures.sh"
RG="rg-sreagent-netops"
SUFFIX="sre-netops-sc"

restore_all_scenarios() {
  "$DEMO" route-blackhole restore >/dev/null 2>&1 || true
  "$DEMO" nsg-deny restore >/dev/null 2>&1 || true
  "$DEMO" asg-detach restore >/dev/null 2>&1 || true
  "$DEMO" peering-disable restore >/dev/null 2>&1 || true
  "$DEMO" firewall-deny restore >/dev/null 2>&1 || true
  "$DEMO" route-table-detach restore >/dev/null 2>&1 || true
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

trap restore_all_scenarios EXIT

echo "1/6 route-blackhole"
"$DEMO" route-blackhole inject
hop="$(az network route-table route show -g "$RG" \
  --route-table-name "rt-spoke1-${SUFFIX}" \
  -n route-to-spoke2-via-firewall --query nextHopType -o tsv)"
[[ "$hop" == "None" ]] || fail "route-blackhole no cambió nextHopType a None"
"$DEMO" route-blackhole restore
hop="$(az network route-table route show -g "$RG" \
  --route-table-name "rt-spoke1-${SUFFIX}" \
  -n route-to-spoke2-via-firewall --query nextHopType -o tsv)"
ip="$(az network route-table route show -g "$RG" \
  --route-table-name "rt-spoke1-${SUFFIX}" \
  -n route-to-spoke2-via-firewall --query nextHopIpAddress -o tsv)"
[[ "$hop" == "VirtualAppliance" && "$ip" == "10.0.0.4" ]] ||
  fail "route-blackhole no restauró VirtualAppliance 10.0.0.4"

echo "2/6 nsg-deny"
"$DEMO" nsg-deny inject
access="$(az network nsg rule show -g "$RG" \
  --nsg-name "nsg-app-spoke2-${SUFFIX}" \
  -n Allow-HTTP-From-Spoke1 --query access -o tsv)"
[[ "$access" == "Deny" ]] || fail "nsg-deny no cambió la regla a Deny"
"$DEMO" nsg-deny restore
access="$(az network nsg rule show -g "$RG" \
  --nsg-name "nsg-app-spoke2-${SUFFIX}" \
  -n Allow-HTTP-From-Spoke1 --query access -o tsv)"
[[ "$access" == "Allow" ]] || fail "nsg-deny no restauró la regla Allow"

echo "3/6 asg-detach"
"$DEMO" asg-detach inject
asg="$(az network nic ip-config show -g "$RG" \
  --nic-name "nic-vm-spoke2-${SUFFIX}" -n ipconfig1 \
  --query 'applicationSecurityGroups[0].id' -o tsv)"
[[ -z "$asg" ]] || fail "asg-detach no eliminó la asociación"
"$DEMO" asg-detach restore
asg="$(az network nic ip-config show -g "$RG" \
  --nic-name "nic-vm-spoke2-${SUFFIX}" -n ipconfig1 \
  --query 'applicationSecurityGroups[0].id' -o tsv)"
[[ "$asg" == */applicationSecurityGroups/asg-app-spoke2-${SUFFIX} ]] ||
  fail "asg-detach no restauró el ASG"

echo "4/6 peering-disable"
"$DEMO" peering-disable inject
vnet_access="$(az network vnet peering show -g "$RG" \
  --vnet-name "vnet-spoke1-${SUFFIX}" -n peer-spoke1-to-hub \
  --query allowVirtualNetworkAccess -o tsv)"
[[ "$vnet_access" == "false" ]] || fail "peering-disable no deshabilitó el acceso"
"$DEMO" peering-disable restore
vnet_access="$(az network vnet peering show -g "$RG" \
  --vnet-name "vnet-spoke1-${SUFFIX}" -n peer-spoke1-to-hub \
  --query allowVirtualNetworkAccess -o tsv)"
forwarded="$(az network vnet peering show -g "$RG" \
  --vnet-name "vnet-spoke1-${SUFFIX}" -n peer-spoke1-to-hub \
  --query allowForwardedTraffic -o tsv)"
[[ "$vnet_access" == "true" && "$forwarded" == "true" ]] ||
  fail "peering-disable no restauró el peering"

echo "5/6 firewall-deny"
"$DEMO" firewall-deny inject
deny_priority="$(az network firewall policy rule-collection-group show -g "$RG" \
  --policy-name "afwp-${SUFFIX}" -n rcg-netops \
  --query "ruleCollections[?name=='rc-injected-deny'].priority | [0]" -o tsv)"
allow_priority="$(az network firewall policy rule-collection-group show -g "$RG" \
  --policy-name "afwp-${SUFFIX}" -n rcg-netops \
  --query "ruleCollections[?name=='rc-allow-east-west'].priority | [0]" -o tsv)"
[[ "$deny_priority" == "100" && "$allow_priority" == "200" ]] ||
  fail "firewall-deny no aplicó prioridades Deny 100 / Allow 200"
"$DEMO" firewall-deny restore
deny_name="$(az network firewall policy rule-collection-group show -g "$RG" \
  --policy-name "afwp-${SUFFIX}" -n rcg-netops \
  --query "ruleCollections[?name=='rc-injected-deny'].name | [0]" -o tsv)"
[[ -z "$deny_name" ]] || fail "firewall-deny no eliminó rc-injected-deny"

echo "6/6 route-table-detach"
"$DEMO" route-table-detach inject
route_table_id="$(az network vnet subnet show -g "$RG" \
  --vnet-name "vnet-spoke1-${SUFFIX}" -n snet-app-spoke1 \
  --query routeTable.id -o tsv)"
[[ -z "$route_table_id" ]] || fail "route-table-detach no eliminó la asociación"
"$DEMO" route-table-detach restore
route_table_id="$(az network vnet subnet show -g "$RG" \
  --vnet-name "vnet-spoke1-${SUFFIX}" -n snet-app-spoke1 \
  --query routeTable.id -o tsv)"
[[ "$route_table_id" == */routeTables/rt-spoke1-${SUFFIX} ]] ||
  fail "route-table-detach no restauró la route table"

trap - EXIT
echo "PASS: los seis escenarios se inyectaron y restauraron correctamente."
