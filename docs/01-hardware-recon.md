# 01 — Hardware reconnaissance (read-only)

Goal: confirm the board family *before* writing anything. Everything here only reads.

## Access to a 2013-era QTS over SSH

QTS 4.0.5 ships an old OpenSSH/Dropbear that only offers `ssh-rsa` / `ssh-dss`. From a modern OpenSSH client:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa -o PreferredAuthentications=password,keyboard-interactive admin@<NAS_IP>
# only if you get "no matching key exchange method":
#   -o KexAlgorithms=+diffie-hellman-group1-sha1
```

The shell is **BusyBox v1.01 (2013)**: no `lsblk`, `free` without `-m`, `md5sum` without `-c`, a `find`
that did not behave with `-exec ... \;` through SSH, no `apt`. `scp` needs the legacy protocol: `scp -O`.
The default admin password after a factory reset is `admin` (change it if you keep QTS as a fallback).

For scripting without typing the password, use `SSH_ASKPASS` (OpenSSH ≥ 8.4):

```sh
printf '#!/bin/sh\necho "$QTS_PASSWORD"\n' > askpass.sh; chmod +x askpass.sh
export SSH_ASKPASS=$PWD/askpass.sh SSH_ASKPASS_REQUIRE=force DISPLAY=:0 QTS_PASSWORD=...
```

## What to collect

```sh
cat /proc/cpuinfo        # Feroceon 88F6282 => Kirkwood "6282" family (not 6281)
getcfg System Model      # prints just "TS-219" on this unit (no "P+")
uname -a                 # Linux 2.6.33.2 armv5tel
cat /proc/mtd            # 6 SPI-NOR partitions (below)
cat /proc/mdstat         # RAID state: wait for [UU] everywhere before heavy work
fdisk -lu /dev/sda       # EXACT start sectors; you need them later
mdadm -E /dev/sda2       # metadata version (0.90 here => superblock at END of partition)
mdadm -E /dev/sda3       # note the UUID of the data array
```

### Values seen on the reference unit (yours will differ)

- CPU: `Feroceon 88F6282 rev 1 (v5l) @ 1.6 GHz`. Under Debian's mainline kernel the same CPU shows as
  `Feroceon 88FR131` with a lower BogoMIPS number, while `cpufreq` reports 1.6 GHz (governor `performance`).
- RAM 512 MB; two SATA ports; one gigabit NIC; PIC microcontroller on UART1 (`/dev/ttyS1`).
- SPI flash: `m25p128`, JEDEC id `20 20 18`, 16 MiB, 256 KiB erase blocks.

```
mtd0: 00080000 "U-Boot"          (512 KiB)   -- NEVER WRITE THIS
mtd1: 00200000 "Kernel"          (2 MiB)
mtd2: 00900000 "RootFS"          (9 MiB)
mtd3: 00300000 "RootFS2"         (3 MiB)
mtd4: 00040000 "U-Boot Config"   (256 KiB)   <- the only partition this procedure changes
mtd5: 00140000 "NAS Config"      (1.25 MiB)
```

Flash address map (not the order shown by `/proc/mtd`):
`0x000000 U-Boot | 0x080000 U-Boot Config | 0x0c0000 NAS Config | 0x200000 Kernel | 0x400000 RootFS | 0xd00000 RootFS2`.

- Disks: MSDOS partition table, 4 primary partitions per disk, mirrored with Linux `md` RAID 1 using
  **metadata 0.90** (the md superblock sits at the *end* of each partition, so the start of an md member is
  the start of the data — a bootloader can read it as a plain disk):

| Partition | md array | Use |
|---|---|---|
| sdX1 | md9 | QTS system/config (ext3) |
| sdX2 | md2 | swap (~517 MB) — **reused for the Debian boot area** |
| sdX3 | md0 | data volume (ext4) |
| sdX4 | md13 | QTS applications |

- Stock boot: U-Boot copies `0xf8200000` (flash kernel) and `0xf8400000` (flash rootfs) into RAM and boots
  with `root=/dev/ram initrd=0xa00000,0x900000 ramdisk=34816`. QTS then unpacks into a ~33 MB ramdisk.

## Is it the same board as the TS-219P II?

Neither community project lists "TS-219P+". The Debian DTB `kirkwood-ts219-6282.dtb` (mainline, board
"QNAP TS219 family", PHY address 0, `s35390a` RTC, PIC poweroff on `serial@12100`) matched this unit in
practice (it booted with working SATA, Ethernet, RTC, PIC). If your CPU line says `88F6281`, use the
`-6281` DTB instead (PHY address 8) — **untested here**.

Next: [02-backup.md](02-backup.md).
