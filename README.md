# Debian 12 + OpenMediaVault 7 on a QNAP TS-219P+ — without touching the stock firmware

> Français : voir [README.fr.md](README.fr.md).

This repository documents how a **QNAP TS-219P+** (Marvell Kirkwood 88F6282, ARMv5TE, 512 MB RAM,
16 MB SPI flash) was moved from QTS 4.0.5 to **Debian 12 (bookworm, armel)** with the
**OpenMediaVault 7** web UI — with a safety net that needs **no serial adapter, no soldering and no
reflashing of the stock kernel/rootfs**.

It contains the procedure, the reasoning, the scripts and the pitfalls hit on the way.
It deliberately contains **no binaries**: no flash dumps, no QNAP firmware, no kernel/initramfs/rootfs
images. You rebuild everything from public sources (see [docs/05](docs/05-build-images.md)).

## The idea in one paragraph

Existing community projects shrink/rewrite the SPI flash so a Debian kernel fits in it. That erases the
stock system and a failed boot is hard to recover without a UART. Here the **stock U-Boot, kernel and
rootfs stay untouched in flash**. Only the 4 KB U-Boot *environment* (256 KB MTD partition) is changed so
U-Boot **loads the Debian kernel + initramfs straight from the SATA disk** (`ide read`, raw sectors at the
end of the old swap partition) and boots it. A *one-shot* mechanism makes U-Boot zero the on-disk kernel
header before every Debian boot; Debian restores it ~60 s later **only if it is healthy** (network + sshd
up). If Debian is broken, the next boot finds an invalid header, `bootm` fails, and U-Boot falls through to
the stock QTS boot command — reachable over the network again. Details: [docs/03](docs/03-boot-architecture.md).

## Status / what was verified

Verified on **one unit** (2 × 500 GB, RAID 1, QTS 4.0.5):

- Debian 12.x armel, kernel 6.1 (`linux-image-marvell`, Debian's `kirkwood-ts219-6282.dtb` appended), boots
  from disk, RAID 1 (`md` 0.90 metadata) assembled by UUID, network 1 Gb/s, fan/LED control via `qcontrol`.
- Automatic fall-back to QTS when the kernel header is zeroed (tested for real, repeatedly).
- OpenMediaVault 7.7 installed by hand from the official repo (which does publish `armel` packages), Samba
  share tested end to end with an SMB client (integrity checked). Idle RAM ≈ 80 MB.
- Full-chain simulation in QEMU (RAID, initramfs scripts, systemd, network, SSH) — see [docs/06](docs/06-test-in-qemu.md).

**Not verified / unknown**: other TS-x19 variants or board revisions (the 88F6282 board here reported
1.6 GHz under QTS), the third-party claim of a 5-minute PIC watchdog (not observed here — see
[docs/10](docs/10-lessons-and-pitfalls.md)), behaviour on power loss during a write, long-term stability
(tested over hours, not weeks), OMV plugins other than `sharerootfs`.

## ⚠️ Risks — read before doing anything

- You write to the SPI flash of a device that has **no recovery path except U-Boot's reset-button TFTP/USB
  recovery** (not tested here). Everything in this repo was done by someone willing to risk the unit.
- **Never write MTD0 (U-Boot).** This procedure only rewrites MTD4 (U-Boot Config, 256 KB), and falls back
  to U-Boot's *built-in default environment* (which boots stock QTS) if that block ever gets corrupted.
- **Security:** Debian 12 no longer receives security updates for `armel`. Keep the NAS on a trusted LAN,
  **never port-forward it** (not even SSH). See [docs/09](docs/09-recovery-and-security.md).
- Back up all six MTD partitions first ([docs/02](docs/02-backup.md)) and keep them private (they contain
  proprietary QNAP code and your device identity).
- No warranty. Use at your own risk. Your numbers (sectors, UUIDs, MAC) will differ — compute them
  ([scripts/pc/compute-layout.py](scripts/pc/compute-layout.py)); never copy example values blindly.

## Repository map

| Path | What |
|---|---|
| [docs/01-hardware-recon.md](docs/01-hardware-recon.md) | Identify the board, flash, disks, RAID, U-Boot (read-only) |
| [docs/02-backup.md](docs/02-backup.md) | Back up the 6 MTD partitions and verify them |
| [docs/03-boot-architecture.md](docs/03-boot-architecture.md) | Disk layout, one-shot boot, U-Boot env design |
| [docs/04-uboot-notes.md](docs/04-uboot-notes.md) | What the stock U-Boot supports (and how it was found) |
| [docs/05-build-images.md](docs/05-build-images.md) | Build rootfs + kernel + initramfs + U-Boot images |
| [docs/06-test-in-qemu.md](docs/06-test-in-qemu.md) | Simulate the whole chain before touching the NAS |
| [docs/07-install-on-nas.md](docs/07-install-on-nas.md) | The actual installation, step by step, with checks |
| [docs/08-openmediavault.md](docs/08-openmediavault.md) | Manual OMV 7 install on armel, shares, passwords |
| [docs/09-recovery-and-security.md](docs/09-recovery-and-security.md) | Going back to QTS, recovery, hardening |
| [docs/10-lessons-and-pitfalls.md](docs/10-lessons-and-pitfalls.md) | Everything that went wrong, and why |
| [docs/11-references.md](docs/11-references.md) | Links (what was actually read vs. only cited) |
| `config.example.env` | Parameters for the build scripts |
| `scripts/pc/` | Build/test tooling (runs on a PC with Docker) |
| `scripts/qts/` | Scripts to run on the NAS while it still runs QTS (BusyBox 1.01 shell) |
| `scripts/debian/` | Files/scripts that end up inside the Debian system |

## Prior art (read these too)

- <https://github.com/amouiche/qnap_mtd_resize_for_bullseye> — re-partitions the flash (kernel 3 MB, rootfs
  12 MB) so Debian 11/12 fits. Established, has a `--dry-run`. No TS-219P+ in its tested list.
- <https://github.com/laserbirdx/qnap-ts-219p-omv> — all-in-one Debian 12 + OMV 7 installer for the
  TS-219P II (loop-root image on the data volume). Very recent; ships prebuilt binaries. This repo borrows
  ideas but **uses none of its code or binaries**.
- Debian dropped QNAP Kirkwood in Debian 11 because the kernel no longer fits the 2 MB kernel partition.
  This design sidesteps that by not using the flash for the kernel at all.

## License

MIT for the content of this repository (see [LICENSE](LICENSE)). Third-party software (Debian, Linux,
U-Boot, OpenMediaVault, QNAP firmware) keeps its own licenses and is not redistributed here.
