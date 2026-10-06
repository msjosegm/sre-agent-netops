#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUB="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || true)}"
LOCATION="swedencentral"
DEPLOYMENT_NAME="sreagent-netops-$(date -u +%Y%m%d%H%M%S)"
MODEL_PROVIDER="${SRE_MODEL_PROVIDER:-MicrosoftFoundry}"
VM_SIZE="${VM_SIZE:-Standard_D2as_v5}"
SKIP_AGENT_CONFIG=false

if [[ "${1:-}" == "--skip-agent-config" ]]; then
  SKIP_AGENT_CONFIG=true
fi

command -v az >/dev/null || { echo "Se requiere Azure CLI." >&2; exit 1; }
[[ -n "$SUB" ]] || { echo "Define AZURE_SUBSCRIPTION_ID o inicia sesión con az login." >&2; exit 1; }
[[ -n "${ADMIN_SSH_PUBLIC_KEY:-}" ]] || { echo "Define ADMIN_SSH_PUBLIC_KEY con una clave pública SSH." >&2; exit 1; }

az account set --subscription "$SUB"
echo "Suscripción: $SUB"
echo "Resource group: rg-sreagent-netops"
echo "Región: $LOCATION"
echo "Tamaño de VM: $VM_SIZE"

az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$ROOT_DIR/infra/main.bicep" \
  --parameters adminSshPublicKey="$ADMIN_SSH_PUBLIC_KEY" sreModelProvider="$MODEL_PROVIDER" vmSize="$VM_SIZE" \
  --output table

NETWORK_WATCHER_JSON="$(az network watcher list \
  --query "[?location=='swedencentral'] | [0].{name:name,resourceGroup:resourceGroup}" \
  --output json)"
NETWORK_WATCHER_NAME="$(jq -r '.name // empty' <<<"$NETWORK_WATCHER_JSON")"
NETWORK_WATCHER_RG="$(jq -r '.resourceGroup // empty' <<<"$NETWORK_WATCHER_JSON")"
[[ -n "$NETWORK_WATCHER_NAME" && -n "$NETWORK_WATCHER_RG" ]] || {
  echo "No se encontró el Network Watcher de Sweden Central." >&2
  exit 1
}

AGENT_JSON="$(az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUB}/resourceGroups/rg-sreagent-netops/providers/Microsoft.App/agents/sre-netops-demo-sc?api-version=2025-05-01-preview" \
  --output json)"
UAMI_PRINCIPAL_ID="$(jq -r '.identity.userAssignedIdentities | to_entries[0].value.principalId // empty' <<<"$AGENT_JSON")"
SAMI_PRINCIPAL_ID="$(jq -r '.identity.principalId // empty' <<<"$AGENT_JSON")"
[[ -n "$UAMI_PRINCIPAL_ID" && -n "$SAMI_PRINCIPAL_ID" ]] || {
  echo "No se pudieron resolver las identidades del agente." >&2
  exit 1
}

az deployment group create \
  --resource-group "$NETWORK_WATCHER_RG" \
  --name deploy-sreagent-network-watcher-rbac \
  --template-file "$ROOT_DIR/infra/modules/network-watcher-rbac.bicep" \
  --parameters \
    networkWatcherName="$NETWORK_WATCHER_NAME" \
    userAssignedPrincipalId="$UAMI_PRINCIPAL_ID" \
    systemAssignedPrincipalId="$SAMI_PRINCIPAL_ID" \
  --output none

if [[ "$SKIP_AGENT_CONFIG" == "false" ]]; then
  "$ROOT_DIR/scripts/configure-agent.sh"
fi

echo "Despliegue completado: $DEPLOYMENT_NAME"
