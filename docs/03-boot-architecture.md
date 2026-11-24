# 03 — Boot architecture

## Why not the usual approach

A Debian ≥ 11 kernel does not fit in the stock 2 MiB kernel partition. The community solution rewrites the
flash layout (and the stock system). If the new kernel then fails to boot, recovery needs a UART or U-Boot's
reset-button recovery. This design keeps the stock flash content intact and puts the Debian kernel on disk.

## Components

```
SPI flash (16 MiB)                       SATA disks (2x, RAID 1, md 0.90)
 ├ U-Boot 1.1.4 (untouched)               ├ sdX1  md9   QTS system         (untouched)
 ├ U-Boot Config  <-- the ONLY change     ├ sdX2  md2   ex-swap
 ├ NAS Config      (untouched)            │    ├ [ ...swap...                ]
 ├ Kernel / RootFS / RootFS2 = QTS        │    ├ [ kernel zone  4 MiB        ]  \  raw sectors,
 │   (untouched, fallback)                │    └ [ initrd zone  8 MiB        ]  /  end of md2
 └ ...                                    ├ sdX3  md0   data (ext4) + /debian  = Debian rootfs
                                          └ sdX4  md13  QTS apps           (untouched)
```

- **Kernel + initramfs** are raw images (`uImage`, `uInitrd`) written at fixed sector numbers at the **end of
  md2** (the old swap array). The end is chosen on purpose: QTS re-enables swap on md2 whenever it boots, and
  swap fills from the *start* of the device. Debian itself never uses md2 as swap (it uses a swap *file*).
- **Debian's root filesystem** is a directory (`/debian`) on the existing md0 ext4 data volume. The initramfs
  assembles md0 by UUID, mounts it, then *bind-mounts* `/debian` as `/` and moves the whole volume to
  `/media/md0` ([scripts/debian/files/local-bottom-subroot](../scripts/debian/files/local-bottom-subroot)).
  The stock QTS data keeps working and stays visible.
- **No flash writes from Debian**: the SPI chip is write-protected by U-Boot and the mainline kernel cannot
  lift the protection (see [10](10-lessons-and-pitfalls.md)). That is why the one-shot flag lives on the
  *disk*, not in the U-Boot environment.

## The U-Boot environment (v3)

Variables are added to the original environment (variable names are arbitrary):

```
klba=<abs LBA of kernel zone>   kcnt=0x2000      # read 8192 sectors = 4 MiB
rlba=<abs LBA of initrd zone>   rcnt=0x4000      # read 16384 sectors = 8 MiB
stock=setenv bootargs console=ttyS0,115200 root=/dev/ram initrd=0xa00000,0x900000 ramdisk=34816;uart1 0x68;cp.l 0xf8200000 0x800000 0x080000;cp.l 0xf8400000 0xa00000 0x240000;bootm 0x800000
debload=ide reset;ide device 0;ide read 0x800000 $(klba) $(kcnt);ide read 0x4000000 $(rlba) $(rcnt);ide device 1;ide read 0x800000 $(klba) $(kcnt);ide read 0x4000000 $(rlba) $(rcnt)
debdis=mw.b 0x2000000 0 200;ide device 0;ide write 0x2000000 $(klba) 1;ide device 1;ide write 0x2000000 $(klba) 1;ide device 0
debargs=setenv bootargs console=ttyS0,115200 root=/dev/md0 rootfstype=ext4 rw rootwait net.ifnames=0
debboot=run debload;run debdis;run debargs;uart1 0x68;bootm 0x800000 0x4000000;run stock
bootcmd=run debboot
```

How it behaves:

1. `debload` reads the kernel image to RAM `0x800000` and the initramfs image to `0x4000000`.
   (This U-Boot only sees *one* SATA disk as device 0; the `ide device 1` lines are harmless extras.)
2. `debdis` writes 512 zero bytes (`mw.b ... 0 200` = 0x200 bytes) over the **first sector of the kernel zone
   on disk**, i.e. it *destroys the uImage header on disk* — but the image is already in RAM.
3. `debargs` sets the kernel command line; `uart1 0x68` keeps the stock call to the PIC; `bootm 0x800000
   0x4000000` boots the kernel with the ramdisk image (header verified by U-Boot, so a damaged initrd also
   falls through).
4. If anything above fails (`bootm` returns on bad magic/CRC), the last command `run stock` runs the stock
   boot sequence → QTS boots.
5. ~60 s after a healthy Debian boot, `qnap-boot-confirm.service` rewrites the saved 512-byte header to the
   kernel zone on **both** disks. Next boot starts Debian again.

Consequence: *every* boot is a trial. If Debian hangs or has no network, power-cycle the box: the header is
still zero, `bootm` fails, QTS boots. U-Boot 1.1.4 (non-hush) keeps executing the remaining commands of a
`;`-chain after one fails; this was observed, not just assumed.

### Properties that make it safe

- `bootcmd` never needs rewriting from Linux; `saveenv` is never used by this design.
- If the env block is corrupted (bad CRC), U-Boot uses its **built-in default environment**, whose
  `bootcmd` boots stock QTS (its own copy of the same `cp.l … bootm` sequence is in the binary).
- The kernel header also acts as a CRC gate: a half-written kernel image (power loss while updating)
  fails `bootm` → QTS.

## Kernel image details

- `uImage` = Debian's `vmlinuz` (a zImage) **concatenated with** `kirkwood-ts219-6282.dtb`, wrapped with
  `mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000`. The Debian marvell kernel has
  `CONFIG_ARM_APPENDED_DTB=y`, `CONFIG_ARM_ATAG_DTB_COMPAT=y` and
  `…_CMDLINE_FROM_BOOTLOADER=y`, so U-Boot's ATAGs (memory, command line, initrd) are merged into the DTB.
- `uInitrd` = the initramfs wrapped with `mkimage -T ramdisk -C none -a 0x01100000 -e 0x01100000`.
  **Do not use load address 0** (see pitfalls). U-Boot copies the ramdisk data to `0x01100000` and passes it
  via `ATAG_INITRD2`; the constant is present in this U-Boot's binary, i.e. it is compiled in.
- RAM map: kernel staged at `0x800000`, ramdisk staged at `0x4000000` (64 MiB, far from the final kernel and
  initrd locations), final ramdisk at `0x1100000`.
- MAC address: the mainline kernel reads it from the Ethernet controller's MAC registers programmed by
  U-Boot. This U-Boot's `ethaddr` is a placeholder (`00:50:43:00:02:02`), so Debian sets the real one with a
  systemd `.link` file (`MACAddress=`), or you set `ethaddr` in the env. Use your NAS's real MAC.

## Sector arithmetic (generated by a script)

`scripts/pc/compute-layout.py` takes: start sector of partition 2, md2 size, image sizes; it prints the
absolute LBAs for `klba`/`rlba` and the relative `seek` values used with `dd` on `/dev/md2`. Reference
numbers (2 × 500 GB, **yours will differ**): partition 2 starts at sector 1060296; md2 has 1060096
sectors; kernel zone at relative sector 1035520, initrd zone at 1043712 (ending exactly at the end of md2).

Next: [04-uboot-notes.md](04-uboot-notes.md).
