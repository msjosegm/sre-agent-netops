#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

command -v bicep >/dev/null || { echo "Se requiere Bicep CLI." >&2; exit 1; }
command -v jq >/dev/null || { echo "Se requiere jq." >&2; exit 1; }

echo "Compilando Bicep..."
bicep build "$ROOT_DIR/infra/main.bicep" --outfile "$TMP_DIR/main.json"
ADMIN_SSH_PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDemoValidationOnlyKey000000000000 demo' \
  bicep build-params "$ROOT_DIR/infra/main.bicepparam" --outfile "$TMP_DIR/main.parameters.json"

echo "Validando JSON del agente..."
find "$ROOT_DIR/agent" -name '*.json' -print0 | while IFS= read -r -d '' file; do
  jq empty "$file"
done

echo "Validando sintaxis de scripts..."
find "$ROOT_DIR/scripts" -name '*.sh' -print0 | while IFS= read -r -d '' file; do
  bash -n "$file"
done

echo "Validación local completada. No se ha desplegado ningún recurso."
