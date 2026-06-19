# Findings: getting Intel & MediaTek Wi-Fi working on JetPack 7.2

A record of *why* these cards don't work on a stock JP7.2 Orin and exactly how each obstacle
was solved, so the next person doesn't have to rediscover it.

Platform: Jetson Orin NX 16GB, Waveshare carrier, **JetPack 7.2** = Jetson Linux **r39.2**,
kernel **`6.8.12-1021-tegra`**, Ubuntu 24.04 (aarch64).

---

## 1. The symptom

An Intel AC 8265 (M.2, PCIe `8086:24fd`) and an Alfa MT7612U (USB `0e8d:7612`) both produce
**no `wlan` interface** — no driver binds. `nmcli` shows no Wi-Fi device.

## 2. Root cause: the kernel doesn't build these drivers

```
# CONFIG_IWLWIFI is not set
```

The tegra kernel ships drivers for `ath10k/ath11k`, `brcmfmac`, `mwifiex`, `mt7921e` (PCIe),
`rsi`, `wl18xx` — but **no Intel `iwlwifi`, no `mt76` USB sub-drivers, and no Realtek
`rtw88/rtw89`** (there is no `realtek/` directory under the built modules at all). That last
point also rules out cards like the Radxa Wireless Module A8 (RTL8852BE) as an "easy swap" —
it needs `rtw89`, which is equally absent.

What *is* present and important: `mac80211`, `cfg80211`, and the `mt76` **core built with USB
support** (`mt76u_*` symbols present).

> Practical escape hatch: a **MediaTek MT7922 M.2** card uses `mt7921e`, which *is* built →
> works with zero effort. Everything below is for when you must use the card you have.

## 3. MediaTek MT7612U (USB) — the easier one

The `mt76` core (with USB) is built; only the MT76x2-USB sub-drivers are off
(`# CONFIG_MT76x2U is not set`). So we only need to build `mt76x2u` + its deps.

### 3.1 Build
Out-of-tree against the running kernel's build dir:

```bash
make -C /lib/modules/$(uname -r)/build M=<src>/drivers/net/wireless/mediatek/mt76 \
  CONFIG_MT76_CORE=m CONFIG_MT76_USB=m CONFIG_MT76x02_LIB=m CONFIG_MT76x02_USB=m \
  CONFIG_MT76x2_COMMON=m CONFIG_MT76x2U=m KCFLAGS="-I<src>/.../mt76" modules
```

### 3.2 Gotcha — modversion clash with the loaded stock core
If the stock tegra `mt76` is already loaded, the freshly built `mt76x2-common` refuses to load:

```
mt76x2_common: disagrees about version of symbol mt76_eeprom_override
```

Fix: build the **whole** mt76 chain (so it's internally consistent), install it to
`updates/`, then **unload the stock mt76 stack first** so our consistent set loads:

```bash
sudo modprobe -r mt76x2u mt76x2_common mt76x02_usb mt76x02_lib \
  mt7921e mt7921_common mt792x_lib mt76_connac_lib mt76_usb mt76
sudo modprobe mt76x2u
```

### 3.3 Gotcha — firmware ships only as `.zst`
```
mt76x2u: Direct firmware load for mt7662_rom_patch.bin failed with error -2
```
The MT7662 firmware is present only as `mt7662*.bin.zst` and the loader can't pull it.
Expand it:
```bash
sudo zstd -dfq -o /lib/firmware/mt7662.bin            /lib/firmware/mt7662.bin.zst
sudo zstd -dfq -o /lib/firmware/mt7662_rom_patch.bin  /lib/firmware/mt7662_rom_patch.bin.zst
```
Reload → `mt76x2u 1-2.1:1.0: ASIC revision: 76120044` and a `wlx…` interface appears.

## 4. Intel iwlwifi — the hard one

### 4.1 Dead ends
- **kernel.org `linux-6.8.12`** source → compile error:
  `cfg/ax210.c: 'iwl_22000_ht_params' undeclared`. The tegra kernel is built from
  **Canonical's Ubuntu-noble** tree (the build dir lives under `3rdparty/canonical/linux-noble`),
  which differs from the kernel.org point release. **Use `linux-source-6.8.0` from apt** — the
  matching base — for the `.c` files.
- A **full in-tree build** from that source → `gcc: error: missing argument to
  '-mstack-protector-guard-offset='`. That offset is computed during the *real* kernel build
  and baked into the installed build dir; a from-scratch build can't reproduce it. So build
  **out-of-tree (`M=`) against `/lib/modules/$(uname -r)/build`**, which inherits the correct
  flags *and* gives the correct module vermagic automatically.
- The `-headers` package has Makefiles and `.h` but **no `.c`** — you must get the driver
  source separately (`linux-source-6.8.0`).
- `backport-iwlwifi` DKMS self-excludes on 6.8 (`BUILD_EXCLUSIVE`) — not usable.

### 4.2 The real blocker: `IS_ENABLED(CONFIG_*)` reads the preprocessor, not make vars
iwlwifi guards both code and exports on the kernel config *as seen by the C preprocessor*
(`include/generated/autoconf.h`), where iwlwifi is disabled. Passing `CONFIG_IWLMVM=m` as a
**make variable** controls *which files compile*, but does **not** define the macro for the
preprocessor. Two symptoms, same cause:

1. `ax210.c` won't compile — the `extern const struct iwl_ht_params iwl_22000_ht_params;` it
   needs is behind `#if IS_ENABLED(CONFIG_IWLMVM)` in `iwl-config.h`.
2. **The exports vanish.** iwlwifi exports via a *custom* macro, roughly:
   ```c
   #if IS_ENABLED(CONFIG_IWLWIFI_OPMODE_MODULAR) || !IS_ENABLED(CONFIG_IWLWIFI)
   #define IWL_EXPORT_SYMBOL(sym)  EXPORT_SYMBOL_NS_GPL(sym, IWLWIFI)
   #else
   #define IWL_EXPORT_SYMBOL(sym)
   #endif
   ```
   Without `CONFIG_IWLWIFI_OPMODE_MODULAR` defined, `IWL_EXPORT_SYMBOL()` expands to *nothing*.
   The core then exports only the ~4 symbols that use plain `EXPORT_SYMBOL`, and `iwlmvm`
   fails at load with `Unknown symbol iwl_*` (err -2). `nm iwlwifi.ko | grep -c __ksymtab_`
   returns **4** instead of **~104**.

Fix: pass the configs as `-D` defines too:
```bash
make -C /lib/modules/$(uname -r)/build M=$SRC \
  CONFIG_IWLWIFI=m CONFIG_IWLMVM=m CONFIG_IWLWIFI_OPMODE_MODULAR=y \
  KCFLAGS="-I$SRC -DCONFIG_IWLWIFI_MODULE=1 -DCONFIG_IWLMVM_MODULE=1 -DCONFIG_IWLWIFI_OPMODE_MODULAR=1" \
  modules
```
Now `ax210.c` compiles, `iwlwifi.ko` exports ~104 symbols, and `iwlmvm.ko` links.

> Side note: during MODPOST you may see `undefined!` warnings for iwlmvm's references to the
> iwlwifi core. Those are harmless — they resolve at load time because the core module loads
> first. They only become real "Unknown symbol" failures if the exports are actually missing
> (i.e. the `-D` above is wrong).

### 4.3 Firmware
The 8265 firmware also ships only `.zst`:
```bash
sudo zstd -dfq -o /lib/firmware/iwlwifi-8265-36.ucode /lib/firmware/iwlwifi-8265-36.ucode.zst
```
After install + `modprobe iwlwifi`:
```
iwlwifi 0001:01:00.0: Detected Intel(R) Dual Band Wireless AC 8265, REV=0x230
iwlwifi 0001:01:00.0: loaded firmware version 36.ca7b901d.0 8265-36.ucode op_mode iwlmvm
iwlwifi 0001:01:00.0 wlP1p1s0: renamed from wlan0
```

## 5. Reboot persistence

Install both `.ko`s to `/lib/modules/$(uname -r)/updates/<driver>/` and run `depmod -a`. The
module device tables generate `modules.alias` entries (PCI `8086:24fd` → iwlwifi; USB
`0e8d:7612` → mt76x2u), so udev auto-loads them on boot. Firmware decompressed to disk
persists. NetworkManager auto-reconnects.

## 6. Generalizing

- Other **Intel** cards (9000-series, AX200/201/210) use the same MVM driver — the same build
  works; just make sure their `iwlwifi-*.ucode` firmware is present (decompress all
  `iwlwifi-*.ucode.zst`).
- **MT7921U** (USB) would follow the MediaTek recipe with `CONFIG_MT7921U=m` (the connac
  chain) instead of the MT76x2 chain.
- **Realtek `rtw89`** (RTL8852/8922) would need the same `linux-source` + `M=` approach, with
  its own `CONFIG_RTW89*` set — not packaged here.

## 7. The one-liner takeaway

> On a Jetson where a driver is *disabled* in the kernel config, build it **out-of-tree with
> `M=` against the installed build dir**, from the **matching Canonical `linux-source`**, and
> pass every relevant `CONFIG_*` as a **`-D` preprocessor define** — not just a make variable —
> because `IS_ENABLED()` reads the preprocessor.
