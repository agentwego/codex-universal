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
check python --version
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
check mockgen -version
check swag -v
check wire flags
check golangci-lint version
check docker --version
check docker buildx version
check docker compose version
check docker-compose version
check task --version
check kubectl version --client=true
check helm version --short
check kustomize version
check talosctl version --client
check flux --version
check sops --version
check age --version
check code-server --version
check node -e "require('/usr/local/lib/code-server-font-proxy/node_modules/http-proxy'); require('fs').accessSync('/usr/local/lib/code-server-font-proxy/server.js')"
check test -s /usr/local/lib/code-server-font-proxy/fonts/CascadiaCode.ttf
check test -d /usr/local/lib/code-server-font-proxy/node_modules/http-proxy
check hermes --version
check hermes doctor --help
check yq --version
check jq --version
check fastfetch --version

echo "Slim image verification completed."
