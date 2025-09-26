#!/usr/bin/env bash
set -euo pipefail

# Automatic setup for WebOpenSSL
# - Installs npm dependencies
# - Builds UMD bundle (dist/webopenssl.min.js) via esbuild
# - Builds OpenSSL WASM provider (dist/openssl-wasm/*) via scripts/build-openssl-wasm.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "== WebOpenSSL automatic setup =="

# Check Node.js
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required (>=16). Please install Node.js and rerun."
  exit 1
fi
NODE_VER="$(node -v)"
NODE_MAJ="${NODE_VER#v}"
NODE_MAJ="${NODE_MAJ%%.*}"
if [ "${NODE_MAJ}" -lt 16 ]; then
  echo "Detected Node.js ${NODE_VER}. Please use Node.js v16 or newer."
  exit 1
fi

# Install dependencies (if any)
if command -v npm >/dev/null 2>&1; then
  echo "Installing npm dependencies..."
  npm install
else
  echo "npm is required. Please install npm and rerun."
  exit 1
fi

# Build UMD bundle
echo "Building UMD bundle (dist/webopenssl.min.js) with esbuild..."
mkdir -p dist
# Use npx with -y to auto-install esbuild if missing
npx -y esbuild src/index.js \
  --bundle \
  --minify \
  --format=umd \
  --global-name=WebOpenSSL \
  --outfile=dist/webopenssl.min.js

# Build OpenSSL WASM provider
echo "Building OpenSSL WASM provider (this may take some time)..."
bash scripts/build-openssl-wasm.sh

echo "== Setup complete =="
echo "Outputs:"
ls -lh dist || true
ls -lh dist/openssl-wasm || true