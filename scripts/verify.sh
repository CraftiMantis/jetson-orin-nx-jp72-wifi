#!/usr/bin/env bash
# Post-install checks.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

echo "== kernel =="; echo "  $KREL"
echo "== loaded Wi-Fi modules =="
lsmod | grep -iE '^iwlwifi|^iwlmvm|^mt76' || echo "  (none loaded)"
echo "== installed out-of-tree modules =="
ls "$UPDATES"/iwlwifi/*.ko "$UPDATES"/mt76/*.ko 2>/dev/null | sed 's#.*/#  #' || echo "  (none in updates/)"
echo "== wlan interfaces =="
ip -br link | grep -iE 'wlP|wlx|wlan' || echo "  (none)"
echo "== NetworkManager Wi-Fi devices =="
nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -i wifi || echo "  (NM sees no wifi)"
echo "== reboot-persistence: auto-load aliases =="
for m in iwlwifi mt76x2u; do
  n="$(grep -cE " ${m}\$" "/lib/modules/$KREL/modules.alias" 2>/dev/null || true)"
  echo "  ${m}: ${n:-0} device alias(es)"
done
echo "== firmware present (uncompressed) =="
ls /lib/firmware/iwlwifi-8265-*.ucode /lib/firmware/mt7662*.bin 2>/dev/null | sed 's#.*/#  #' || echo "  (none)"
