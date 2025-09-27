#!/usr/bin/env bash
set -euo pipefail

# Build OpenSSL (libcrypto) to WebAssembly using Emscripten and emit a modularized JS factory.
# Output: dist/openssl-wasm/openssl_module.js + openssl_module.wasm
#
# Prereqs:
# - Bash, curl, tar, make, perl
# - Emscripten SDK (emsdk) or this script will fetch and activate it locally
#
# Notes:
# - We export a tiny wrapper function `openssl_rand_bytes(ptr, len)` built against libcrypto.
# - WebOpenSSL will auto-load this module if present and use it as the provider.
#
# Tested against OpenSSL 3.5.3 (latest stable at time of writing).
# Official releases: https://github.com/openssl/openssl/releases/latest

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/dist/openssl-wasm"
BUILD_DIR="${ROOT}/build/openssl-wasm"
EMSDK_DIR="${ROOT}/.emsdk"
OPENSSL_VER="3.5.3"
OPENSSL_TAG="openssl-${OPENSSL_VER}"
OPENSSL_TARBALL_URL="https://www.openssl.org/source/${OPENSSL_TAG}.tar.gz"
NPROC="$(command -v nproc >/dev/null && nproc || echo 4)"

mkdir -p "${OUT_DIR}"
mkdir -p "${BUILD_DIR}"

function ensure_emsdk() {
  if command -v emcc >/dev/null 2>&1; then
    echo "Found emcc in PATH."
    return
  fi
  echo "Emscripten not found in PATH. Installing local emsdk into ${EMSDK_DIR}..."
  if [ ! -d "${EMSDK_DIR}" ]; then
    git clone https://github.com/emscripten-core/emsdk.git "${EMSDK_DIR}"
  fi
  pushd "${EMSDK_DIR}" >/dev/null
  ./emsdk install latest
  ./emsdk activate latest
  # shellcheck disable=SC1091
  source ./emsdk_env.sh
  popd >/dev/null
}

function fetch_openssl() {
  local src_dir="${BUILD_DIR}/src"
  mkdir -p "${src_dir}"
  if [ ! -d "${src_dir}/${OPENSSL_TAG}" ]; then
    echo "Downloading ${OPENSSL_TAG}..."
    curl -L "${OPENSSL_TARBALL_URL}" -o "${src_dir}/${OPENSSL_TAG}.tar.gz"
    echo "Extracting ${OPENSSL_TAG}.tar.gz..."
    tar -xzf "${src_dir}/${OPENSSL_TAG}.tar.gz" -C "${src_dir}"
  fi
}

function build_openssl_libcrypto() {
  local ossl_dir="${BUILD_DIR}/src/${OPENSSL_TAG}"
  pushd "${ossl_dir}" >/dev/null

  echo "Configuring OpenSSL for Emscripten..."
  # Ensure em* tools are picked up
  export CC=emcc
  export AR=emar
  export RANLIB=emranlib
  export CFLAGS="-O3 -fPIC"
  export LDFLAGS="-O3"

  # Some environments set CROSS_COMPILE; OpenSSL's build system may prefix $(CC) with it.
  # That can produce broken paths like .../emscripten/em/.../emcc. Ensure it's empty.
  unset CROSS_COMPILE || true
  export CROSS_COMPILE=""

  # Configure OpenSSL directly (no emconfigure) to avoid CROSS_COMPILE prefixing bugs.
  # Target a generic 32-bit linux and disable unsupported features in WASM.
  # Explicitly disable Linux-only engines (AFALG/devcrypto) and the engine subsystem entirely.
  perl ./Configure linux-generic32 no-asm no-shared no-threads no-dso no-ui no-tests no-engine no-afalgeng no-devcryptoeng -DOPENSSL_NO_SECURE_MEMORY

  echo "Building libcrypto (this can take a while)..."
  make -j"${NPROC}" build_generated
  make -j"${NPROC}" libcrypto.a

  if [ ! -f "libcrypto.a" ]; then
    echo "ERROR: libcrypto.a not found after build"
    exit 1
  fi

  popd >/dev/null
}

function build_wrapper_module() {
  local ossl_dir="${BUILD_DIR}/src/${OPENSSL_TAG}"
  local wrapper_src="${ROOT}/src/wasm/openssl_rand_wrapper.c"

  if [ ! -f "${wrapper_src}" ]; then
    echo "ERROR: Wrapper C file not found at ${wrapper_src}"
    exit 1
  fi

  echo "Linking wrapper against libcrypto and emitting modularized JS factory..."
  emcc "${wrapper_src}" -O3 \
    -I "${ossl_dir}/include" \
    -L "${ossl_dir}" -lcrypto \
    -s MODULARIZE=1 \
    -s EXPORT_NAME=OpenSSLModuleFactory \
    -s ENVIRONMENT=web,worker,node \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s NO_FILESYSTEM=1 \
    -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
    -s EXPORTED_FUNCTIONS="['_openssl_rand_bytes','_pbkdf2_hmac_sha256','_pbkdf2_hmac_sha512','_sha256_digest','_sha512_digest','_aes_256_gcm_encrypt','_aes_256_gcm_decrypt','_malloc','_free']" \
    -s EXPORTED_RUNTIME_METHODS="['cwrap']" \
    -o "${OUT_DIR}/openssl_module.js"

  echo "Done. Output placed in: ${OUT_DIR}"
  ls -lh "${OUT_DIR}"
}

ensure_emsdk
fetch_openssl
build_openssl_libcrypto
build_wrapper_module

echo "OpenSSL WASM build completed."