#!/usr/bin/env bash
# One-shot setup: detect the Wi-Fi card(s), build + install the matching driver(s), load.
#
# Usage:
#   sudo ./setup.sh            # auto-detect installed card(s) and build accordingly
#   sudo ./setup.sh iwlwifi    # force-build the Intel iwlwifi driver
#   sudo ./setup.sh mt76x2u    # force-build the MediaTek MT7612U USB driver
#   sudo ./setup.sh rtw89      # force-build the Realtek RTL8852BE driver
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/scripts/lib.sh"

require_jp72

FORCE="${1:-}"
HAVE_INTEL=0; HAVE_MT7612=0; HAVE_RTL8852=0

log "Detecting Wi-Fi hardware..."
if lspci -nn 2>/dev/null | grep -iE 'Network controller|Wireless' | grep -qi 'Intel'; then
  HAVE_INTEL=1; log "  Intel Wi-Fi (PCIe) detected"
fi
if lsusb 2>/dev/null | grep -qiE '0e8d:7612'; then
  HAVE_MT7612=1; log "  MediaTek MT7612U (USB) detected"
fi
if lspci -nn 2>/dev/null | grep -qiE '10ec:b852|RTL8852'; then
  HAVE_RTL8852=1; log "  Realtek RTL8852BE (PCIe) detected"
fi
[[ $HAVE_INTEL -eq 0 && $HAVE_MT7612 -eq 0 && $HAVE_RTL8852 -eq 0 && -z "$FORCE" ]] && \
  warn "No supported card auto-detected. Pass 'iwlwifi', 'mt76x2u', or 'rtw89' to force a build."

bash "$HERE/scripts/00-prereqs.sh"
if [[ $HAVE_INTEL -eq 1   || "$FORCE" == "iwlwifi" ]]; then bash "$HERE/scripts/build-iwlwifi.sh"; fi
if [[ $HAVE_MT7612 -eq 1  || "$FORCE" == "mt76x2u" ]]; then bash "$HERE/scripts/build-mt76x2u.sh"; fi
if [[ $HAVE_RTL8852 -eq 1 || "$FORCE" == "rtw89"   ]]; then bash "$HERE/scripts/build-rtw89.sh";   fi

echo
bash "$HERE/scripts/verify.sh"
cat <<'EOF'

-----------------------------------------------------------------------
Driver(s) built, installed to /lib/modules/$(uname -r)/updates/, and loaded.
They auto-load on boot (udev modalias) and survive reboots.

Connect with NetworkManager:
  sudo nmcli device wifi rescan
  sudo nmcli device wifi connect '<SSID>' password '<PSK>'

NOTE: a kernel update changes the build target — re-run ./setup.sh afterwards.
-----------------------------------------------------------------------
EOF
