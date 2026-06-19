# Wi-Fi drivers for Jetson Orin NX on JetPack 7.2

JetPack 7.2 (Jetson Linux **r39.2**, kernel **`6.8.12-1021-tegra`**, Ubuntu 24.04) ships a
kernel that **does not build a driver for most common M.2 / USB Wi-Fi cards** — including
Intel and Realtek parts, and the MediaTek *USB* family. If you drop one of these cards into
an Orin and nothing shows up under `ip link` / `nmcli`, this is why.

This repo builds the missing drivers from the **matching kernel source** and installs them so
the card works and survives reboots. Verified on an Orin NX 16GB (Waveshare carrier), JP7.2.

```bash
git clone <this-repo> && cd jetson-orin-nx-jp72-wifi
sudo ./setup.sh                       # auto-detects the card and builds the right driver
# then:
sudo nmcli device wifi connect '<SSID>' password '<PSK>'
```

## What works out of the box, and what doesn't

The JP7.2 tegra kernel **builds** drivers for: `ath10k/ath11k` (Qualcomm), `brcmfmac`
(Broadcom), `mwifiex` (Marvell), **`mt7921e` (MediaTek MT7921/MT7922 PCIe/M.2)**, `rsi`, and
`wl18xx` (TI). The wireless core (`mac80211`, `cfg80211`) and the `mt76` core (with USB
support) are present too.

It does **not** build:

| Card / chipset | Driver | In JP7.2? | This repo |
|---|---|---|---|
| Intel AC 8265 / 9000 / AX2xx | `iwlwifi` + `iwlmvm` | ❌ `# CONFIG_IWLWIFI is not set` | ✅ `build-iwlwifi.sh` |
| MediaTek **MT7612U** (USB, e.g. Alfa AWUS036ACM) | `mt76x2u` | ❌ (mt76 core yes, USB sub-drivers no) | ✅ `build-mt76x2u.sh` |
| MediaTek MT7921U (USB) | `mt7921u` | ❌ | (same approach, not packaged here) |
| Realtek RTL8852BE (e.g. Radxa Wireless Module A8) | `rtw89` | ❌ (no `realtek/` dir at all) | (not packaged here) |
| MediaTek **MT7922 (M.2/PCIe)** | `mt7921e` | ✅ **works out of the box** | — |

**Buying advice:** if you just want Wi-Fi with zero effort on this platform, get a
**MediaTek MT7922 M.2** card — `mt7921e` is already built.

## Supported by the scripts here

- **Intel `iwlwifi`** (MVM family — AC 8260/8265, 9000-series, AX200/AX201/AX210) — PCIe/M.2
- **MediaTek `mt76x2u`** (MT7612U) — USB

## How it works (short version)

The full story is in [FINDINGS.md](FINDINGS.md). The essentials:

1. **Use the right source.** The tegra kernel is built from **Canonical's Ubuntu-noble** tree
   (`.../3rdparty/canonical/linux-noble`), not kernel.org. Building from kernel.org 6.8.12
   fails. We use `linux-source-6.8.0` from apt (the matching base) for the driver `.c` files.
2. **Build out-of-tree (`M=`) against the installed kernel build dir** — not a full in-tree
   build. The build dir carries the correct vermagic and the baked
   `-mstack-protector-guard-offset` that a from-scratch build can't reproduce.
3. **Pass the driver `CONFIG_*` as `-D` preprocessor defines, not just make variables.**
   iwlwifi gates both code and its symbol exports behind `IS_ENABLED(CONFIG_*)`, which reads
   `autoconf.h` (where the driver is disabled). Critically, `CONFIG_IWLWIFI_OPMODE_MODULAR`
   gates the custom `IWL_EXPORT_SYMBOL()` macro — miss it and the core exports ~4 symbols
   instead of ~100, so `iwlmvm` can't load.
4. **Fix up firmware.** Some firmware ships only `.zst`-compressed and the loader returns
   `-2`; the scripts expand the needed blobs to plain files.

## Reboot persistence

Modules install to `/lib/modules/$(uname -r)/updates/` and `depmod` registers the device
aliases, so udev auto-loads them on boot. Firmware is decompressed to disk. Connect once with
NetworkManager (`autoconnect` defaults on) and it reconnects automatically.

## Caveat: kernel updates

These modules are tied to the exact running kernel (`uname -r`). If the kernel is updated,
**re-run `sudo ./setup.sh`** to rebuild against the new kernel. (On Jetson a JetPack bump is a
full reflash anyway.)

## Files

```
setup.sh                 # detect card(s) -> build -> install -> load
scripts/00-prereqs.sh    # toolchain + matching kernel source
scripts/build-iwlwifi.sh # Intel iwlwifi (MVM)
scripts/build-mt76x2u.sh # MediaTek MT7612U (USB)
scripts/verify.sh        # post-install checks
scripts/lib.sh           # shared helpers
FINDINGS.md              # full technical write-up / debugging trail
```

## Notes

- The built modules are unsigned; loading them taints the kernel (`module verification
  failed`). That is expected for out-of-tree modules and is harmless here.
- `iwlwifi` here builds the **MVM** opmode (modern cards). The legacy **DVM** opmode
  (5000/6000-series) is not enabled.
