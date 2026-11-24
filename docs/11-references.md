# 11 — References

"Read" = the content was actually retrieved and inspected while doing this work. "Cited" = known/pointed to but
not opened here.

## Community projects (prior art)

| Link | Status | What it is |
|---|---|---|
| <https://github.com/amouiche/qnap_mtd_resize_for_bullseye> | read (README, `qnap_mtd_resize.py`, `Recovery.md`) | Re-partitions the SPI flash (kernel 3 MB, rootfs 12 MB) so Debian 11/12 fits; `--dry-run`; documents restoring stock firmware from your own MTD dumps. TS-219P+ not in its tested table. |
| <https://github.com/laserbirdx/qnap-ts-219p-omv> | read (README, `docs/UART.md`, `installer/install-from-qts.sh`, boot `init`) | Debian 12 + OMV 7 for the TS-219P II, loop-root image on the data volume; UART wiring (CN1) and TFTP boot notes. Ships prebuilt binaries — **none used here**. |
| <https://www.cyrius.com/debian/kirkwood/qnap/ts-219/install> | cited | Debian's historical installer page for the TS-219 (Debian ≤ 10). |

## Debian / OpenMediaVault

| Link | Status | Note |
|---|---|---|
| <https://www.debian.org/releases/bookworm/armel/ch02s01.en.html> | cited (search result) | Debian 12 armel supported hardware (Kirkwood images exist, none for QNAP). |
| <https://forum.openmediavault.org/index.php?thread/44303-install-omv-on-an-armbian-qnap-ts-219p/> | cited (search result summary) | The OMV maintainer's stance: no armel support in the install script/omv-extras. |
| <https://github.com/openmediavault/openmediavault/issues/1996> | cited (search result summary) | OMV 8 drops i386/armel/armhf (Salt is amd64/arm64 only). |
| <https://openmediavault.github.io/packages/dists/sandworm/Release> | read | OMV 7 repo: `Architectures: i386 amd64 armel armhf arm64`. `…/main/binary-armel/Packages.gz` lists 30 packages incl. `openmediavault 7.7.x`, `salt-minion 3006`, `php-pam`, `wsdd-server`, `openmediavault-sharerootfs`. (`packages.openmediavault.org` redirects there; use `curl -L`.) |
| <https://raw.githubusercontent.com/OpenMediaVault-Plugin-Developers/installScript/master/install> | read | Official install script (current branch targets OMV 8); shows the steps replicated by hand and the `arm64\|amd64` architecture check. |
| Debian packages `linux-image-marvell` (→ `linux-image-6.1.0-*-marvell`), `qcontrol`, `libubootenv-tool`, `u-boot-tools`, `mtd-utils`, `mdadm`, `initramfs-tools` | read (content of the first two) | The kernel package ships `kirkwood-ts219-6282.dtb` and `-6281.dtb`; `qcontrol` ships `ts219.lua` and `/etc/qcontrol.conf`. |

## Linux kernel sources consulted (v6.1)

- `arch/arm/mach-mvebu/kirkwood.c` — `kirkwood_dt_eth_fixup()`: MAC address read back from the Ethernet controller
  registers (`MV643XX_ETH_MAC_ADDR_LOW/HIGH`) programmed by the bootloader.
- `arch/arm/boot/dts/kirkwood-ts219.dtsi`, `kirkwood-ts219-6282.dts` — board description (PHY node `reg` overridden per
  variant: `<0>` for 6282), `s35390a` RTC, `gpio-keys`, `qnap,power-off` on UART1.
- `arch/arm/boot/compressed/atags_to_fdt.c` — with `CONFIG_ARM_ATAG_DTB_COMPAT`, U-Boot's `ATAG_CMDLINE`, `ATAG_MEM`
  and `ATAG_INITRD2` are merged into the appended DTB (`/chosen/linux,initrd-start|end`).

(Fetched from `git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/<path>?h=v6.1.176` and
`raw.githubusercontent.com/torvalds/linux/v6.1/<path>`.)

## Tooling

- `tonistiigi/binfmt` (Docker image) to register QEMU user-mode emulation for ARM in the Docker VM.
- `debootstrap`, `u-boot-tools` (`mkimage`), `device-tree-compiler` (`dtc`), `mdadm`, `qemu-system-arm`.
- `libubootenv-tool` (`fw_printenv`) to validate environment images offline.
- Python: `smbprotocol` (SMB client used for validation), `capstone` was installed for U-Boot disassembly but not
  needed in the end (string/constant scanning was enough).
