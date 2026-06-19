#!/usr/bin/env bash
# Build + install the Intel iwlwifi driver (MVM family: AC 8260/8265, 9000-series,
# AX200/AX201/AX210...) for Jetson JetPack 7.2.
#
# The stock JP7.2 kernel is configured with `# CONFIG_IWLWIFI is not set`, so there is
# no Intel Wi-Fi driver at all. We build it from the matching Canonical kernel source.
#
# Two non-obvious requirements (see FINDINGS.md):
#   * iwlwifi guards code and exports behind IS_ENABLED(CONFIG_*), which reads the
#     PREPROCESSOR (autoconf.h, where iwlwifi is OFF) — NOT the make variables. So the
#     relevant CONFIG_* must also be passed as -D defines.
#   * CONFIG_IWLWIFI_OPMODE_MODULAR specifically gates the custom IWL_EXPORT_SYMBOL()
#     macro; without it the core exports ~4 symbols instead of ~100 and iwlmvm cannot
#     load ("Unknown symbol iwl_*").
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_jp72
ensure_kernel_source

SRCROOT="$WORK/iwl"
log "Extracting iwlwifi source from $SRC_TARBALL ..."
rm -rf "$SRCROOT"; mkdir -p "$SRCROOT"
tar xf "$SRC_TARBALL" -C "$SRCROOT" --wildcards "*/drivers/net/wireless/intel/iwlwifi/*"
SRC="$(find "$SRCROOT" -type d -path '*/intel/iwlwifi' | head -1)"
[[ -n "$SRC" && -f "$SRC/cfg/ax210.c" ]] || die "iwlwifi source not extracted under $SRCROOT"

log "Building iwlwifi + iwlmvm (out-of-tree M= against $KBUILD)..."
make -C "$KBUILD" M="$SRC" clean >/dev/null 2>&1 || true
make -C "$KBUILD" M="$SRC" \
  CONFIG_IWLWIFI=m CONFIG_IWLMVM=m CONFIG_IWLWIFI_OPMODE_MODULAR=y \
  KCFLAGS="-I$SRC -DCONFIG_IWLWIFI_MODULE=1 -DCONFIG_IWLMVM_MODULE=1 -DCONFIG_IWLWIFI_OPMODE_MODULAR=1" \
  modules

EXPORTS="$(nm "$SRC/iwlwifi.ko" 2>/dev/null | grep -c '__ksymtab_' || true)"
log "iwlwifi.ko exports $EXPORTS symbols."
[[ "${EXPORTS:-0}" -ge 50 ]] || die "Only $EXPORTS exports — the IWL_EXPORT_SYMBOL guard did not open.
   Check that -DCONFIG_IWLWIFI_OPMODE_MODULAR=1 is in KCFLAGS."

log "Installing modules to $UPDATES/iwlwifi ..."
sudo mkdir -p "$UPDATES/iwlwifi"
sudo cp "$SRC/iwlwifi.ko" "$SRC/mvm/iwlmvm.ko" "$UPDATES/iwlwifi/"
sudo depmod -a

log "Decompressing Intel firmware (.ucode.zst -> .ucode) ..."
decompress_fw "/lib/firmware/iwlwifi-*.ucode.zst"

log "Loading iwlwifi ..."
sudo modprobe -r iwlmvm iwlwifi 2>/dev/null || true
sudo modprobe iwlwifi
sleep 4

if ip -br link | grep -qiE 'wlP|wlan'; then
  log "Intel Wi-Fi up:"; ip -br link | grep -iE 'wlP|wlan'
else
  warn "No Intel wlan interface yet. Inspect: sudo dmesg | grep -i iwlwifi"
fi
