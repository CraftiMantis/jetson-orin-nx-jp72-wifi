#!/usr/bin/env bash
# Build + install the MediaTek mt76x2u driver (MT7612U USB Wi-Fi, e.g. Alfa AWUS036ACM)
# for Jetson JetPack 7.2.
#
# The JP7.2 kernel builds the mt76 *core* (with USB support) and mt7921 (PCIe), but NOT
# the MT76x2 USB sub-drivers (CONFIG_MT76x2U is off). We build the whole mt76 chain from
# the matching kernel source so the built set is internally consistent.
#
# Gotchas (see FINDINGS.md):
#   * If the stock tegra mt76 core is already loaded, the freshly built mt76x2-common
#     fails with "disagrees about version of symbol ..." — so unload the tegra mt76 stack
#     first, then load our consistent set from updates/.
#   * The MT7662 firmware ships only .zst-compressed and must be expanded to plain .bin.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_jp72
ensure_kernel_source

SRCROOT="$WORK/mt76"
log "Extracting mt76 source from $SRC_TARBALL ..."
rm -rf "$SRCROOT"; mkdir -p "$SRCROOT"
tar xf "$SRC_TARBALL" -C "$SRCROOT" --wildcards "*/drivers/net/wireless/mediatek/mt76/*"
SRC="$(find "$SRCROOT" -type d -path '*/mediatek/mt76' | head -1)"
[[ -n "$SRC" && -d "$SRC/mt76x2" ]] || die "mt76 source not extracted under $SRCROOT"

log "Building mt76 USB chain (mt76x2u + deps) against $KBUILD ..."
make -C "$KBUILD" M="$SRC" clean >/dev/null 2>&1 || true
make -C "$KBUILD" M="$SRC" \
  CONFIG_MT76_CORE=m CONFIG_MT76_USB=m CONFIG_MT76_LEDS=y \
  CONFIG_MT76x02_LIB=m CONFIG_MT76x02_USB=m CONFIG_MT76x2_COMMON=m CONFIG_MT76x2U=m \
  KCFLAGS="-I$SRC" modules
[[ -f "$SRC/mt76x2/mt76x2u.ko" ]] || die "mt76x2u.ko was not produced"

log "Installing the full self-built mt76 set to $UPDATES/mt76 (updates/ overrides the stock kernel modules)..."
sudo mkdir -p "$UPDATES/mt76"
sudo find "$SRC" -name "*.ko" -exec cp {} "$UPDATES/mt76/" \;
sudo depmod -a

log "Decompressing MediaTek MT7662 firmware (.bin.zst -> .bin) ..."
decompress_fw "/lib/firmware/mt7662*.bin.zst"
decompress_fw "/lib/firmware/mediatek/mt7662*.bin.zst"

log "Unloading any pre-loaded stock mt76 stack (avoids modversion clash) ..."
sudo modprobe -r mt76x2u mt76x2_common mt76x02_usb mt76x02_lib \
  mt7921e mt7921_common mt792x_lib mt76_connac_lib mt76_usb mt76 2>/dev/null || true

log "Loading mt76x2u ..."
sudo modprobe mt76x2u
sleep 4

if ip -br link | grep -qiE 'wlx|wlan'; then
  log "MediaTek USB Wi-Fi up:"; ip -br link | grep -iE 'wlx|wlan'
else
  warn "No wlan interface yet. Inspect: sudo dmesg | grep -iE 'mt76|mt7662'"
fi
