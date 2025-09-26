#!/usr/bin/env bash
set -euo pipefail

# Automatic project setup script for WebOpenSSL.
# - Builds the minified UMD bundle at dist/webopenssl.min.js using esbuild (via npx)
# - Optionally builds the OpenSSL WASM provider (pass --with-wasm)
#
# Usage:
#   bash scripts/setup.sh
#   bash scripts/setup.sh --with-wasm    # also builds the WASM provider
#
# Requirements:
# - Node.js >= 16 with npm
# - Bash, curl (for optional WASM build path)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT}/dist"
WITH_WASM=0

for arg in "$@"; do
  case "$arg" in
    --with-wasm) WITH_WASM=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

function need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

echo "==> Checking prerequisites..."
need_cmd node
need_cmd npm
need_cmd npx

mkdir -p "${DIST_DIR}"

echo "==> Building UMD bundle (dist/webopenssl.min.js) with esbuild..."
# Use npx to avoid editing package.json dependencies. This fetches esbuild if not cached.
npx --yes esbuild "${ROOT}/src/index.js" \
  --bundle \
  --minify \
  --platform=browser \
  --format=iife \
  --global-name=WebOpenSSL \
  --outfile="${DIST_DIR}/webopenssl.min.js"

echo "==> Bundle built at: ${DIST_DIR}/webopenssl.min.js"

if [ "${WITH_WASM}" -eq 1 ]; then
  echo "==> Building OpenSSL WASM provider..."
  bash "${ROOT}/scripts/build-openssl-wasm.sh"
else
  echo "==> Skipping WASM build (pass --with-wasm to enable)"
fi

echo "==> Setup complete."