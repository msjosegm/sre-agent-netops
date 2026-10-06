#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="${RESOURCE_GROUP_NAME:-rg-sreagent-netops}"
AGENT="${SRE_AGENT_NAME:-sre-netops-demo-sc}"
SUB="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || true)}"
API_VERSION="2025-05-01-preview"

[[ -n "$SUB" ]] || { echo "AZURE_SUBSCRIPTION_ID no está definido y no hay sesión de Azure CLI." >&2; exit 1; }
command -v az >/dev/null || { echo "Se requiere Azure CLI." >&2; exit 1; }
command -v jq >/dev/null || { echo "Se requiere jq." >&2; exit 1; }
command -v curl >/dev/null || { echo "Se requiere curl." >&2; exit 1; }

az account set --subscription "$SUB"
ARM_BASE="https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.App/agents/${AGENT}"
AGENT_JSON="$(az rest --method GET --url "${ARM_BASE}?api-version=${API_VERSION}" -o json)"
ENDPOINT="$(jq -r '.properties.agentEndpoint // empty' <<<"$AGENT_JSON")"
[[ -n "$ENDPOINT" ]] || { echo "No se pudo resolver el endpoint del agente." >&2; exit 1; }
TOKEN="$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)"

put_extended() {
  local kind="$1"
  local name="$2"
  local type="$3"
  local properties="$4"
  local body response code
  body="$(jq -nc --arg name "$name" --arg type "$type" --argjson properties "$properties" \
    '{name:$name,type:$type,tags:[],properties:$properties}')"

  echo "Configurando ${kind}/${name}"
  response="$(curl --silent --show-error \
    --write-out $'\n%{http_code}' \
    --request PUT \
    --url "${ENDPOINT}/api/v2/extendedAgent/${kind}/${name}" \
    --header "Authorization: Bearer ${TOKEN}" \
    --header "Content-Type: application/json" \
    --data "$body")"
  code="$(tail -n 1 <<<"$response")"
  [[ "$code" =~ ^2 ]] || {
    echo "Error configurando ${kind}/${name}: HTTP ${code}" >&2
    sed '$d' <<<"$response" >&2
    exit 1
  }
}

put_knowledge_source() {
  local file="$1"
  local filename name content_type content body response code existing_code
  filename="$(basename "$file")"
  name="$(printf '%s' "${filename%.*}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-32)"
  content_type="text/markdown"
  content="$(base64 <"$file" | tr -d '\n')"
  body="$(jq -nc \
    --arg name "$name" \
    --arg filename "$filename" \
    --arg contentType "$content_type" \
    --arg content "$content" \
    '{
      name:$name,
      type:"KnowledgeItem",
      tags:[],
      properties:{
        dataConnectorType:"KnowledgeFile",
        dataSource:$name,
        extendedProperties:{
          displayName:$filename,
          fileName:$filename,
          fileContent:$content,
          contentType:$contentType
        }
      }
    }')"

  echo "Configurando Knowledge Source ${filename}"
  existing_code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --header "Authorization: Bearer ${TOKEN}" \
    "${ENDPOINT}/api/v2/extendedAgent/connectors/${name}")"
  if [[ "$existing_code" =~ ^2 ]]; then
    echo "Knowledge Source ${filename} ya existe; se conserva."
    return 0
  fi

  response="$(curl --silent --show-error \
    --write-out $'\n%{http_code}' \
    --request PUT \
    --url "${ENDPOINT}/api/v2/extendedAgent/connectors/${name}" \
    --header "Authorization: Bearer ${TOKEN}" \
    --header "Content-Type: application/json" \
    --data "$body")"
  code="$(tail -n 1 <<<"$response")"
  [[ "$code" =~ ^2 ]] || {
    echo "Error configurando Knowledge Source ${filename}: HTTP ${code}" >&2
    sed '$d' <<<"$response" >&2
    exit 1
  }
}

verify_named_resource() {
  local kind="$1"
  local name="$2"
  curl --silent --show-error --fail \
    --header "Authorization: Bearer ${TOKEN}" \
    "${ENDPOINT}/api/v2/extendedAgent/${kind}/${name}" >/dev/null
}

COMMON_NAME="$(jq -r '.name' "$ROOT_DIR/agent/common-prompts/netops-guardrails.json")"
COMMON_PROPS="$(jq -c '.properties' "$ROOT_DIR/agent/common-prompts/netops-guardrails.json")"
put_extended "commonprompts" "$COMMON_NAME" "CommonPrompt" "$COMMON_PROPS"

SKILL_NAME="$(jq -r '.metadata.name' "$ROOT_DIR/agent/skills/network-triage.json")"
SKILL_PROPS="$(jq -c '{
  name:.metadata.name,
  description:(.metadata.description // ""),
  tools:(.metadata.spec.tools // []),
  skillContent:(.skillContent // ""),
  additionalFiles:(.additionalFiles // [])
}' "$ROOT_DIR/agent/skills/network-triage.json")"
SKILL_PROPS="${SKILL_PROPS//__SUBSCRIPTION_ID__/$SUB}"
put_extended "skills" "$SKILL_NAME" "Skill" "$SKILL_PROPS"

SUBAGENT_NAME="$(jq -r '.metadata.name' "$ROOT_DIR/agent/subagents/network-operator.json")"
SUBAGENT_PROPS="$(jq -c '.spec' "$ROOT_DIR/agent/subagents/network-operator.json")"
put_extended "agents" "$SUBAGENT_NAME" "ExtendedAgent" "$SUBAGENT_PROPS"

FILTER_NAME="$(jq -r '.metadata.name' "$ROOT_DIR/agent/incident-filters/network-alert-response.json")"
FILTER_PROPS="$(jq -c '.spec' "$ROOT_DIR/agent/incident-filters/network-alert-response.json")"
put_extended "incidentFilters" "$FILTER_NAME" "IncidentFilter" "$FILTER_PROPS"

TASK_NAME="$(jq -r '.metadata.name' "$ROOT_DIR/agent/scheduled-tasks/network-watch.json")"
TASK_PROPS="$(jq -c '.spec | {
  name:(.name // ""),
  description:(.description // ""),
  cronExpression:(.schedule // ""),
  agentPrompt:(.prompt // ""),
  agent:(.handlingAgent // ""),
  agentMode:(.mode // "Review"),
  isEnabled:(.enabled // true)
}' "$ROOT_DIR/agent/scheduled-tasks/network-watch.json")"
put_extended "scheduledtasks" "$TASK_NAME" "ScheduledTask" "$TASK_PROPS"

for knowledge_file in "$ROOT_DIR"/agent/knowledge/*.md; do
  put_knowledge_source "$knowledge_file"
done

verify_named_resource "commonprompts" "$COMMON_NAME"
verify_named_resource "skills" "$SKILL_NAME"
verify_named_resource "agents" "$SUBAGENT_NAME"
verify_named_resource "incidentFilters" "$FILTER_NAME"
verify_named_resource "scheduledtasks" "$TASK_NAME"

KNOWLEDGE_COUNT="$(curl --silent --show-error --fail \
  --header "Authorization: Bearer ${TOKEN}" \
  "${ENDPOINT}/api/v2/extendedAgent/connectors" |
  jq '[.value[]? | select((.properties.dataConnectorType // "") | startswith("Knowledge"))] | length')"
[[ "$KNOWLEDGE_COUNT" -ge 3 ]] || {
  echo "Se esperaban al menos 3 Knowledge Sources y se encontraron ${KNOWLEDGE_COUNT}." >&2
  exit 1
}

echo "Configuración del agente completada y verificada."
