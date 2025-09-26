#!/usr/bin/env bash
# Automatic setup of system dependencies for this project.
# - Detects OS/package manager and installs required build tools and utilities.
# - Installs Node.js and npm (skips if already present).
# - Ensures tools needed by scripts/build-openssl-wasm.sh (curl, git, tar, make, perl, python, pkg-config).
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
set -euo pipefail

# Determine whether to use sudo when needed
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

pm=""
os="$(uname -s)"

detect_pm() {
  if [ "$os" = "Darwin" ]; then
    pm="brew"
    return
  fi
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    like="${ID_LIKE:-}"
    id="${ID:-}"
    sig="$(printf "%s %s" "$id" "$like" | tr '[:upper:]' '[:lower:]')"
    if echo "$sig" | grep -qiE 'debian|ubuntu'; then
      pm="apt"
      return
    elif echo "$sig" | grep -qiE 'fedora|rhel|centos'; then
      if command -v dnf >/dev/null 2>&1; then
        pm="dnf"
      else
        pm="yum"
      fi
      return
    elif echo "$sig" | grep -qiE 'arch'; then
      pm="pacman"
      return
    elif echo "$sig" | grep -qiE 'alpine'; then
      pm="apk"
      return
    fi
  fi
  # Fallback: probe common managers
  for candidate in apt dnf yum pacman apk brew; do
    if command -v "$candidate" >/dev/null 2>&1; then
      pm="$candidate"
      return
    fi
  done
}

detect_pm

if [ -z "$pm" ]; then
  echo "Unsupported OS or package manager not found."
  echo "Please install required tools manually: git, curl, tar, make, perl, python3/pip, pkg-config, Node.js/npm."
  exit 1
fi

have_node="no"
if command -v node >/dev/null 2>&1; then
  have_node="yes"
fi

log "Detected package manager: $pm"

update_index() {
  case "$pm" in
    apt)
      $SUDO apt-get update
      ;;
    dnf)
      $SUDO dnf -y makecache
      ;;
    yum)
      # Metadata refresh is implicit on install for many systems
      ;;
    pacman)
      $SUDO pacman -Sy --noconfirm
      ;;
    apk)
      $SUDO apk update
      ;;
    brew)
      brew update
      ;;
  esac
}

install_packages() {
  case "$pm" in
    apt)
      pkgs=(git curl tar make perl python3 python3-pip pkg-config build-essential)
      if [ "$have_node" = "no" ]; then
        pkgs+=(nodejs npm)
      fi
      $SUDO apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      pkgs=(git curl tar make perl python3 python3-pip pkgconf-pkg-config gcc gcc-c++)
      if [ "$have_node" = "no" ]; then
        pkgs+=(nodejs npm)
      fi
      $SUDO dnf install -y "${pkgs[@]}"
      ;;
    yum)
      pkgs=(git curl tar make perl python3 python3-pip pkgconfig gcc gcc-c++)
      if [ "$have_node" = "no" ]; then
        pkgs+=(nodejs npm)
      fi
      $SUDO yum install -y "${pkgs[@]}"
      ;;
    pacman)
      # Arch: python package provides Python 3; pkgconf provides pkg-config
      pkgs=(git curl tar make perl python pkgconf base-devel)
      if [ "$have_node" = "no" ]; then
        pkgs+=(nodejs npm)
      fi
      $SUDO pacman -S --noconfirm --needed "${pkgs[@]}"
      ;;
    apk)
      pkgs=(git curl tar make perl python3 py3-pip pkgconf build-base)
      if [ "$have_node" = "no" ]; then
        pkgs+=(nodejs npm)
      fi
      $SUDO apk add --no-cache "${pkgs[@]}"
      ;;
    brew)
      # macOS: system tar/make/perl exist; ensure pkg-config, python, node, git, curl
      pkgs=(git curl python pkg-config node)
      brew install "${pkgs[@]}"
      ;;
  esac
}

log "Refreshing package index..."
update_index
log "Installing required system packages..."
install_packages

log "Verifying installations..."
if command -v git >/dev/null 2>&1; then git --version | sed 's/^/[setup] /'; else log "git missing"; fi
if command -v curl >/dev/null 2>&1; then curl --version | head -n1 | sed 's/^/[setup] /'; else log "curl missing"; fi
if command -v pkg-config >/dev/null 2>&1; then pkg-config --version | sed 's/^/[setup] /'; else log "pkg-config missing"; fi
if command -v python3 >/dev/null 2>&1; then python3 --version | sed 's/^/[setup] /'; elif command -v python >/dev/null 2>&1; then python --version | sed 's/^/[setup] /'; else log "python missing"; fi
if command -v node >/dev/null 2>&1; then node -v | sed 's/^/[setup] /'; else log "node missing (skipped install because it appears present earlier or not available via manager)"; fi
if command -v npm >/dev/null 2>&1; then npm -v | sed 's/^/[setup] /'; else log "npm missing"; fi

echo "[setup] Done. You can now run project builds, e.g.:"
echo "[setup]   npm run build:wasm"