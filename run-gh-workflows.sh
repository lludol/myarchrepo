#!/usr/bin/env bash

# Trigger all "Update *" GitHub Actions workflows (workflow_dispatch).
# Requires: gh CLI, authenticated (gh auth login).
# Excludes built-in workflows like pages-build-deployment.

set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: 'gh' is not installed or not in PATH."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if ! gh auth status -h github.com &>/dev/null; then
  echo "Error: Not authenticated with GitHub. Run: gh auth login -h github.com"
  exit 1
fi

echo "Fetching workflow list..."
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  echo "Triggering: $name"
  gh workflow run "$name" || true
done < <(gh workflow list --limit 200 | awk '/^Update / {print $1, $2}')

echo
echo "Done. Check runs at: $(gh repo view --json url -q .url)/actions"
