#!/usr/bin/env bash

# Env file: .secrets.act
# SKIP_CREATE_PR=true
# GH_API_TOKEN=XXXX

set -euo pipefail

if ! command -v act >/dev/null 2>&1; then
  echo "Error: 'act' is not installed or not in PATH."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ACT_IMAGE="${ACT_IMAGE:-ghcr.io/catthehacker/ubuntu:full-latest}"
SECRETS_FILE="${SECRETS_FILE:-.secrets.act}"

declare -A WORKFLOWS=()
WORKFLOW_KEYS=()

discover_workflows() {
  local file key
  shopt -s nullglob
  for file in .github/workflows/update-*.yml .github/workflows/update-*.yaml; do
    key="$(basename "$file")"
    key="${key#update-}"
    key="${key%.yml}"
    key="${key%.yaml}"
    WORKFLOWS["$key"]="$file"
    WORKFLOW_KEYS+=("$key")
  done
  shopt -u nullglob

  if [[ ${#WORKFLOW_KEYS[@]} -eq 0 ]]; then
    echo "No update-* workflows found in .github/workflows"
    exit 1
  fi

  mapfile -t WORKFLOW_KEYS < <(printf '%s\n' "${WORKFLOW_KEYS[@]}" | sort)
}

usage() {
  echo "Usage: $0 [all|<workflow-name>...]"
  echo
  echo "Examples:"
  echo "  $0 all"
  echo "  $0 zoom"
  echo "  $0 tradingview fastmail mongodb-compass-bin"
  echo
  echo "Optional env vars:"
  echo "  ACT_IMAGE=<runner-image>   (default: $ACT_IMAGE)"
  echo "  SECRETS_FILE=<file>        (default: $SECRETS_FILE)"
  echo
  echo "Discovered workflow names:"
  printf '  - %s\n' "${WORKFLOW_KEYS[@]}"
}

ensure_secrets_file() {
  if [[ -f "$SECRETS_FILE" ]]; then
    return
  fi

  cat > "$SECRETS_FILE" <<'EOF'
SKIP_CREATE_PR=true
GH_API_TOKEN=dummy
EOF
  echo "Created $SECRETS_FILE with local-safe defaults."
}

run_one() {
  local key="$1"
  local workflow="${WORKFLOWS[$key]:-}"

  if [[ -z "$workflow" ]]; then
    echo "Unknown workflow key: $key"
    usage
    exit 2
  fi

  echo
  echo "==> Running $key ($workflow)"
  act workflow_dispatch \
    -W "$workflow" \
    -j check-and-update \
    --secret-file "$SECRETS_FILE" \
    --pull=false \
    -P "ubuntu-latest=$ACT_IMAGE"
}

main() {
  discover_workflows

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  ensure_secrets_file

  if [[ $# -eq 0 || "${1:-}" == "all" ]]; then
    local key
    for key in "${WORKFLOW_KEYS[@]}"; do
      run_one "$key"
    done
    exit 0
  fi

  local item
  for item in "$@"; do
    run_one "$item"
  done
}

main "$@"
