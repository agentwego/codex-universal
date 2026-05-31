#!/usr/bin/env bash
set -euo pipefail

echo "Verifying slim cloud development image ..."

check() {
  echo "- $*"
  "$@"
}

check git --version
check gh --version
check python3 --version
check uv --version
check ruff --version
check black --version
check poetry --version
check node --version
check npm --version
check pnpm --version
check tsc --version
check tsx --version
check go version
check kubectl version --client=true
check helm version --short
check kustomize version
check talosctl version --client
check flux --version
check sops --version
check age --version
check code-server --version
check hermes --version
check hermes doctor --help
check yq --version
check jq --version

echo "Slim image verification completed."
