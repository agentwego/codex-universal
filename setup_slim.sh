#!/usr/bin/env bash
set -euo pipefail

if [ -n "${CODEX_ENV_PYTHON_VERSION:-}" ]; then
  echo "# Python: slim image ships system Python only"
  python3 --version
fi

if [ -n "${CODEX_ENV_NODE_VERSION:-}" ]; then
  echo "# Node.js: slim image ships a single Node major"
  node --version
fi

if [ -n "${CODEX_ENV_GO_VERSION:-}" ]; then
  echo "# Go: slim image ships a single Go version"
  go version
fi

if [ -n "${CODEX_ENV_RUST_VERSION:-}" ] || [ -n "${CODEX_ENV_SWIFT_VERSION:-}" ] || [ -n "${CODEX_ENV_RUBY_VERSION:-}" ] || [ -n "${CODEX_ENV_PHP_VERSION:-}" ] || [ -n "${CODEX_ENV_JAVA_VERSION:-}" ]; then
  echo "# This slim image intentionally omits Rust/Swift/Ruby/PHP/Java version managers."
fi
