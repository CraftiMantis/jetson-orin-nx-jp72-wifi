#!/usr/bin/env bash
# Build + install the Realtek rtw89 driver (RTL8852BE — e.g. Radxa Wireless Module A8)
# for Jetson JetPack 7.2.
#
# The stock JP7.2 kernel ships NO Realtek rtw89 at all (there is no realtek/ directory
# under the built wireless modules), so an RTL8852/8922 card has no driver out of the box.
#
# Unlike iwlwifi, rtw89 uses plain EXPORT_SYMBOL — it builds cleanly with just the make
# vars + an include path; no -D preprocessor defines are needed.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_jp72
ensure_kernel_source

SRCROOT="$WORK/rtw89"
log "Extracting rtw89 source from $SRC_TARBALL ..."
rm -rf "$SRCROOT"; mkdir -p "$SRCROOT"
tar xf "$SRC_TARBALL" -C "$SRCROOT" --wildcards "*/drivers/net/wireless/realtek/rtw89/*"
SRC="$(find "$SRCROOT" -type d -path '*/realtek/rtw89' | head -1)"
[[ -n "$SRC" && -f "$SRC/pci.c" ]] || die "rtw89 source not extracted under $SRCROOT"

log "Building rtw89 (core + pci + 8852b + 8852be) against $KBUILD ..."
make -C "$KBUILD" M="$SRC" clean >/dev/null 2>&1 || true
make -C "$KBUILD" M="$SRC" \
  CONFIG_RTW89=m CONFIG_RTW89_CORE=m CONFIG_RTW89_PCI=m \
  CONFIG_RTW89_8852B=m CONFIG_RTW89_8852B_COMMON=m CONFIG_RTW89_8852BE=m \
  KCFLAGS="-I$SRC" modules
[[ -f "$SRC/rtw89_8852be.ko" ]] || die "rtw89_8852be.ko was not produced"

log "Installing modules to $UPDATES/rtw89 ..."
sudo mkdir -p "$UPDATES/rtw89"
sudo find "$SRC" -name "*.ko" -exec cp {} "$UPDATES/rtw89/" \;
sudo depmod -a

log "Decompressing RTL8852B firmware (.zst -> .bin) ..."
decompress_fw "/lib/firmware/rtw89/rtw8852b*.bin.zst"

log "Loading rtw89_8852be ..."
sudo modprobe -r rtw89_8852be 2>/dev/null || true
sudo modprobe rtw89_8852be
sleep 4

if ip -br link | grep -qiE 'wlP|wlan'; then
  log "RTL8852BE Wi-Fi up:"; ip -br link | grep -iE 'wlP|wlan'
else
  warn "No wlan interface yet. Inspect: sudo dmesg | grep -i rtw89"
fi
