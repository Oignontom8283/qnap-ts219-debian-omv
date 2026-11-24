# 06 — Simulate the chain in QEMU before touching the NAS

QEMU has **no Kirkwood machine**, so the real marvell kernel and U-Boot cannot be emulated. What *can* be
tested — and caught three real bugs here — is everything from the initramfs onwards:

- md RAID 1 assembly with 0.90 metadata by UUID and `AUTO -all`,
- the initramfs-tools scripts (including the `/debian` bind-mount),
- systemd boot of your real rootfs, networkd DHCP, sshd with your key,
- that the existing data on md0 remains visible under `/media/md0`.

The harness builds a **generic armhf kernel** (`linux-image-armmp`) with an initramfs that uses the *same*
config/scripts as the real one (plus virtio drivers), creates two disk images with a RAID 1 containing your
rootfs under `/debian`, and boots them with `qemu-system-arm -M virt,highmem=off`.

```sh
sh scripts/pc/qemu-test.sh          # builds the test kernel, creates disks, boots QEMU in a container
docker logs -f nasqemu              # ~3-4 min until the login prompt (everything is emulated)
ssh -i secrets/nas_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@127.0.0.1 \
  'findmnt -no SOURCE,FSROOT,TARGET /; ls /media/md0; systemctl is-system-running; ip -4 -br addr'
```

Expected: root = `/dev/md0[/debian]` mounted on `/`, the whole volume at `/media/md0` (your `Share/test.txt`
is there), `eth0` with a `10.0.2.x` address, `systemctl is-system-running` = `running` or `degraded` with only
`mdmonitor` failed (no mail config — harmless).

## What the simulation found (bugs fixed before reaching the NAS)

1. The initramfs had **no busybox** (it was a "recommended" package excluded by `--no-install-recommends`),
   so Debian's mdadm script died with `rm: not found` and the RAID never assembled.
2. DNS inside the build chroot silently broke after `systemd-resolved` was installed (it replaces
   `resolv.conf` with a dead symlink), failing the later kernel package download.
3. Not found by QEMU but found while preparing it: the ramdisk wrapper used load address 0 (see pitfalls).

## Harness gotchas

- `-M virt,highmem=off` is required with the generic armhf kernel, otherwise `pci-host-generic … error -16`
  and no disks appear.
- The rootfs only contains the *marvell* kernel's modules, so the test initramfs must carry the virtio
  drivers (`virtio_blk`, `virtio_net`, …) — they stay loaded after the pivot.
- md/loop devices live in the **Docker VM's kernel** and survive container deletion. A leftover `md0` with the
  same UUID makes the next run fail with "/dev/md0 is already in use". `make-disks-and-run.sh` cleans up first.
- systemd inside an *emulated Docker container* fails some units with `status=243/CREDENTIALS`; that is a
  container artifact, not a rootfs problem — use the full QEMU system boot instead.

## What it does NOT prove

U-Boot behaviour, the `ide` commands, the Debian marvell kernel on this SoC, the DTB, SATA/Ethernet/PIC drivers
on the real board. Those were validated on the NAS itself, under the safety net of [03](03-boot-architecture.md).

Next: [07-install-on-nas.md](07-install-on-nas.md).
