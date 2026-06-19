#!/usr/bin/env bash
# Shared helpers for the Jetson Orin NX (JetPack 7.2) Wi-Fi driver builds.
# Sourced by the other scripts; not meant to be run directly.

set -euo pipefail

KREL="$(uname -r)"
KBUILD="/lib/modules/${KREL}/build"
UPDATES="/lib/modules/${KREL}/updates"

# JetPack 7.2 / Jetson Linux r39.2 ships kernel 6.8.12-*-tegra, which is built from
# Canonical's Ubuntu-noble tree. The matching driver .c source is therefore the noble
# kernel source (NOT kernel.org 6.8.12 — that tree differs enough to break the build).
SRC_VER="${SRC_VER:-6.8.0}"
SRC_TARBALL="/usr/src/linux-source-${SRC_VER}.tar.bz2"

WORK="${WORK:-/tmp/orin-wifi-build}"

log()  { printf '\033[1;32m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require_jp72() {
  case "$KREL" in
    *-tegra) : ;;
    *) die "Kernel '$KREL' is not a Tegra kernel. This repo targets Jetson JetPack 7.2." ;;
  esac
  [[ -d "$KBUILD" ]] || die "Kernel build dir missing: $KBUILD
   Install the L4T kernel headers for this kernel first."
  [[ -f "$KBUILD/Module.symvers" ]] || warn "No Module.symvers in $KBUILD — module symbol versioning may be off."
}

ensure_kernel_source() {
  if [[ ! -f "$SRC_TARBALL" ]]; then
    log "Installing linux-source-${SRC_VER} (Canonical noble base that matches this kernel)..."
    sudo apt-get update -y
    sudo apt-get install -y "linux-source-${SRC_VER}"
  fi
  [[ -f "$SRC_TARBALL" ]] || die "linux-source tarball not found: $SRC_TARBALL"
}

# Decompress any *.zst firmware matching a glob into plain files (the in-kernel loader
# on this image does not transparently handle the shipped .zst firmware for these drivers).
decompress_fw() {
  command -v zstd >/dev/null || sudo apt-get install -y zstd
  shopt -s nullglob
  local f
  for f in $1; do
    [[ "$f" == *.zst ]] || continue
    sudo zstd -dfq -o "${f%.zst}" "$f" && log "firmware: ${f%.zst}"
  done
  shopt -u nullglob
}
