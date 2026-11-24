# 10 — Lessons and pitfalls (everything that bit, and why)

Ordered roughly by how dangerous each one was.

## Boot-chain pitfalls

1. **Ramdisk load address 0 would have destroyed the boot.** `mkimage -T ramdisk -a 0 -e 0` makes U-Boot copy the
   ramdisk data to address 0, over the kernel it just placed. Use an explicit, free address
   (`0x01100000`). Spotted by reading what U-Boot does with `ih_load`, not by testing.
2. **Linux cannot write this SPI flash.** U-Boot enables chip-wide block protection (`sflash protect` /
   "write protection to ALL"). The Debian kernel's `MEMUNLOCK` returns `EINVAL` for the bottom partitions (the
   ST-style lock ranges only grow from the top), `MEMERASE`/`write()` return success, and `fw_setenv` exits 0 — but
   the chip ignores everything. `strace` shows erase+write "succeeding"; reading `/dev/mtd4` shows the old data.
   This is why the one-shot flag lives on the disk. Writes **from QTS** work (its old driver clears the protection).
3. **U-Boot's `saveenv` works**, but it cannot be used for a *Debian-confirmed* flag because Debian cannot write
   the env back. A first design (U-Boot does `setenv bootcmd run stock; saveenv` before booting Debian, Debian
   re-arms with `fw_setenv`) therefore failed, and was replaced by the on-disk header mechanism.
4. **`ide device 1` does nothing; Linux's `sda`/`sdb` names are not stable** across boots while U-Boot's device 0
   is a fixed physical port. The marker written by the *same* U-Boot script landed on `sdb2` in one boot and on
   `sda2` in the next. Hence: write everything to both disks; restore both headers.
5. **Swap vs boot zones**: QTS re-enables swap on md2 on every boot. The first layout (zones at the start of
   md2) would have been overwritten by swap use; the zones now sit at the very end. If you ever see a bad CRC at
   boot after running QTS with memory pressure, rewrite the zones.
6. **Check that a claimed fall-back really loads something.** Reading laserbirdx's install script (not run here): it appends `bootm 0x900000` as a "legacy" fall-back, but the same script overwrites the old kernel region with the tail of the new image, so on a bad kernel `0x900000` would point into the middle of the Debian image. amouiche's design is different and consistent (its 3 MB read from flash `0x100000` also pulls the legacy kernel to `0x900000`). Verify such claims from the offsets before trusting them.
7. **Where a failed boot does NOT fall back**: if the kernel starts but then hangs, nothing resets the box. The
   design relies on you power-cycling it once; the next boot is QTS. No watchdog was involved.
8. The third-party claim of a **PIC 5-minute watchdog** (U-Boot arms it with `uart1 0x68`, the OS must send
   `0x67`) was **not observed** on the reference unit: under QTS `ttyS1` showed `tx:0` after an hour, and the
   first Debian boot ran 8+ minutes with nothing sent to the PIC. The `uart1 0x68` call is kept as in the stock
   `bootcmd`. If your unit powers off ~5 minutes after Debian starts, that is the cause: send `0x67` ('g') on
   `/dev/ttyS1` at 19200 baud early in the initramfs.

## Build / initramfs pitfalls

9. **`--no-install-recommends` drops busybox from the initramfs** → `rm: not found`, RAID never assembled
   (found in QEMU).
10. **`systemd-resolved` replaces `/etc/resolv.conf` in the chroot** with a symlink to a runtime file that does not
    exist there → later `apt` fails with "Temporary failure resolving".
11. `fw_setenv -s script` (libubootenv) does **not** take `name value` lines; they were stored as variables whose
    *name* contained the whole line. Use one `fw_setenv name value` per variable for offline experiments.
12. Building the rootfs on an **NTFS bind mount** loses Unix permissions/special files: build in a Docker volume.
13. `grep` on a raw 500 MB block device (one "line") exhausted the NAS's 512 MB RAM (OOM messages in dmesg). Use a
    chunked reader (Python) for raw-device searches.
14. Docker Desktop: stale `md`/loop devices survive `docker rm` (they live in the VM's kernel) and make the next
    test fail with "/dev/md0 is already in use".

## QTS-side pitfalls (BusyBox 1.01, kernel 2.6.33)

15. `md5sum -c` does not exist; `find -exec … \;` produced no output over ssh (a shell `while read` loop works);
    `scp` needs `-O`.
16. `/dev/mtd4` (char) cannot be read; `/dev/mtdblockN` can. The block layer flushes on `sync`.
17. **Read-back after writing through `/dev/md2` can be stale** when you read `/dev/sdX` directly (separate page
    cache). `echo 3 > /proc/sys/vm/drop_caches` first. A "failed" verification cost several steps before this was
    understood (the data was actually fine).
18. `reboot` over SSH was ignored the first time on two occasions; check `uptime`.
19. `getcfg System Model` says only "TS-219" for this TS-219P+.

## Debian/hardware observations

20. Debian got a **different DHCP address** than QTS (lease memory / client id). Plan for scanning the subnet.
21. The mainline kernel takes the MAC from the Ethernet controller registers set by U-Boot; this U-Boot's `ethaddr`
    is a placeholder (`00:50:43:00:02:02`), hence the systemd `.link` file.
22. `qcontrol` (Debian package, profile `ts219`) talks to the PIC on `ttyS1`: temperature, fan levels, LEDs,
    buzzer, buttons through `gpio_keys`. It worked on this board.
23. The CPU shows `88FR131` and a low BogoMIPS under the mainline kernel while `cpufreq` reports 1.6 GHz — not a problem.
24. Boot time: Debian→Debian ≈ 1 min; via QTS ≈ 2.5–3 min.

## Windows-side note (environment specific)

25. On the reference PC, `net use \\IP\share` failed with error 67 even towards `127.0.0.1` (and `net view` with
    1702) — a broken *local* SMB client, unrelated to the NAS. The server was validated with `smbprotocol`
    instead; a plain PowerShell listing of `\\NAS\Public` worked later.
