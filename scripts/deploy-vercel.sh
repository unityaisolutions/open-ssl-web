#!/usr/bin/env bash
set -euo pipefail

# Deploy the project to Vercel.
# Steps:
# 1) Build fresh WASM (npm run build:wasm)
# 2) Create/refresh the vercel-build folder by copying the project (excluding dev/build artifacts)
# 3) Move examples/index.html to vercel-build/index.html and rewrite relative paths
# 4) Deploy vercel-build with Vercel CLI
#
# Prerequisites (one-time):
# - npm i -g vercel
# - vercel login
# - vercel link --cwd vercel-build   (must exist; this script preserves .vercel)
#
# Notes:
# - We preserve vercel-build/.vercel across runs so linking only needs to happen once.
# - This script requires bash, rsync (optional), and sed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT}/vercel-build"

# Check Vercel CLI
if ! command -v vercel >/dev/null 2>&1; then
  echo "ERROR: vercel CLI not found."
  echo "Install with: npm i -g vercel"
  exit 1
fi

echo "==> Step 1/4: Building fresh WASM"
npm run build:wasm

echo "==> Step 2/4: Preparing vercel-build folder"
mkdir -p "${BUILD_DIR}"

# Clean vercel-build except the .vercel metadata (to keep project link)
if [ -d "${BUILD_DIR}" ]; then
  shopt -s dotglob
  for item in "${BUILD_DIR}"/*; do
    name="$(basename "${item}")"
    if [ "${name}" != ".vercel" ]; then
      rm -rf "${item}"
    fi
  done
  shopt -u dotglob
fi

# Copy project files to vercel-build while excluding unwanted directories
echo "Copying project files into vercel-build..."
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude '.gitignore' \
    --exclude '.DS_Store' \
    --exclude 'build' \
    --exclude '.emsdk' \
    --exclude 'vercel-build' \
    --exclude '.vercel' \
    "${ROOT}/" "${BUILD_DIR}/"
else
  echo "rsync not found; using cp fallback"
  shopt -s dotglob
  for entry in "${ROOT}"/*; do
    base="$(basename "${entry}")"
    case "${base}" in
      node_modules|.git|.gitignore|.DS_Store|build|.emsdk|vercel-build|.vercel)
        continue
        ;;
    esac
    cp -a "${entry}" "${BUILD_DIR}/"
  done
  shopt -u dotglob
fi

# Move examples/index.html to the root of vercel-build and rewrite paths
INDEX_SRC="${BUILD_DIR}/examples/index.html"
INDEX_DST="${BUILD_DIR}/index.html"

if [ -f "${INDEX_SRC}" ]; then
  echo "==> Step 3/4: Moving examples/index.html to vercel-build/index.html"
  mv -f "${INDEX_SRC}" "${INDEX_DST}"
else
  echo "WARNING: ${INDEX_SRC} not found. Ensure your demo page exists at examples/index.html"
fi

# Cross-platform sed inline helper
sedi() {
  # $1 = pattern, $2 = file
  if sed --version >/dev/null 2>&1; then
    sed -i -e "$1" "$2"
  else
    sed -i '' -e "$1" "$2"
  fi
}

if [ -f "${INDEX_DST}" ]; then
  echo "Rewriting relative paths inside index.html"
  # Rewrite ../dist/... -> dist/...
  sedi 's|src="../dist/|src="dist/|g' "${INDEX_DST}"
  sedi 's|href="../dist/|href="dist/|g' "${INDEX_DST}"
  sedi "s|url: '../dist/|url: 'dist/|g" "${INDEX_DST}"
  sedi 's|url: "../dist/|url: "dist/|g' "${INDEX_DST}"

  # Rewrite ../src/... -> src/...
  sedi 's|src="../src/|src="src/|g' "${INDEX_DST}"
  sedi 's|href="../src/|href="src/|g' "${INDEX_DST}"
  sedi "s|url: '../src/|url: 'src/|g" "${INDEX_DST}"
  sedi 's|url: "../src/|url: "src/|g' "${INDEX_DST}"
fi

# Ensure the Vercel project is linked
if [ ! -f "${BUILD_DIR}/.vercel/project.json" ]; then
  echo "ERROR: Vercel project is not linked for ${BUILD_DIR}."
  echo "Run once to link this build directory:"
  echo "  vercel link --cwd ${BUILD_DIR}"
  exit 1
fi

echo "==> Step 4/4: Deploying vercel-build to Vercel (production)"
vercel deploy --cwd "${BUILD_DIR}" --prod --yes

echo "Deployment triggered. If this is your first deployment, Vercel will provide a URL."