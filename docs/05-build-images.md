# 05 — Build the images (on a PC, with Docker)

Nothing is built on the NAS: its CPU is slow and QTS has no toolchain. Everything is built in Linux
containers on your PC; ARM binaries run through QEMU user-mode emulation (`binfmt`).

## Prerequisites

- Docker with Linux containers (Docker Desktop on Windows works; the repository's scripts were run from Git Bash).
- ~10 GB free disk, a working internet connection.
- A POSIX shell and Python 3 on the host (Git Bash is fine on Windows).

## Steps

```sh
cp config.example.env config.env          # then edit: MD0_UUID, NAS_MAC, NAS_HOSTNAME, layout numbers
mkdir secrets
ssh-keygen -t ed25519 -N "" -f secrets/nas_ed25519          # key used for SSH into Debian
python -c "import secrets,string;a=string.ascii_letters+string.digits;print(''.join(secrets.choice(a) for _ in range(20)))" > secrets/root_password.txt
sh scripts/pc/build.sh
```

`config.env` and `secrets/` are git-ignored. The build takes roughly 10–15 minutes (debootstrap second stage
and the kernel/initramfs packages run under emulation).

What `build.sh` does ([container-build-rootfs.sh](../scripts/pc/container-build-rootfs.sh) and
[chroot-setup.sh](../scripts/debian/chroot-setup.sh)):

1. Registers ARM emulation in the Docker VM (`tonistiigi/binfmt --install arm`).
2. `debootstrap --foreign --arch=armel` of Debian 12, second stage inside the chroot.
3. Installs `initramfs-tools`, `mdadm`, `busybox` **first**, then sets `MODULES=list`, `COMPRESS=gzip`, the module
   list, the `local-bottom` bind-mount script and an `mdadm.conf` that names only your md0 UUID (`AUTO -all`),
   so no other array is auto-assembled.
4. Installs the base system (systemd, sshd, networkd, resolved, timesyncd, mtd/uboot tools, smartmontools…).
5. Installs `linux-image-marvell` (the metapackage; at the time: 6.1.0-50) so the initramfs is generated with
   the configuration from step 3. Restores a working `/etc/resolv.conf` first (see pitfalls).
6. Writes root password + your SSH public key, the hostname, the `.link` file that sets your MAC.
7. Takes `vmlinuz`, the initramfs and `kirkwood-ts219-6282.dtb`, concatenates kernel + DTB, and wraps both
   with `mkimage` (kernel `-a/-e 0x8000`; ramdisk **`-a/-e 0x01100000`**).
8. Archives the rootfs as `out/rootfs.tar`.

Outputs (all git-ignored; **never publish them**): `out/uImage` (~2.6 MB), `out/uInitrd` (~6.7 MB),
`out/uImage.hdr` (the first 512 bytes of the kernel image), `out/rootfs.tar` (~335 MB).

## Check the initramfs before going further

```sh
mkdir /tmp/x && cd /tmp/x && zcat <repo>/out/initrd.img | cpio -idm
ls bin/busybox bin/rm sbin/mdadm                # busybox/rm MUST exist
cat etc/mdadm/mdadm.conf                        # must contain your md0 UUID
find . -name '*.ko*' | sed 's#.*/##' | sort     # sata_mv, md_mod, raid1, ext4, jbd2, mbcache, ...
ls scripts/local-bottom                         # mdadm  qnap-subroot  (in that order, see ORDER)
```

## Sector layout and padding

```sh
python scripts/pc/pad-images.py out/uImage out/uInitrd          # -> *.pad (whole sectors, with md5)
python scripts/pc/compute-layout.py <PART2_START_SECTOR> <MD2_SECTORS> out/uImage out/uInitrd
python scripts/pc/make-env.py mtd4-backup.bin out/mtd4.new.bin <klba> <kcnt> <rlba> <rcnt>   # values printed above
```

Validate `out/mtd4.new.bin` offline ([04](04-uboot-notes.md)) — e.g. in a throw-away container:
`apt-get install libubootenv-tool; fw_printenv -c fw_env.config` with a `fw_env.config` pointing at the file.

Next: [06-test-in-qemu.md](06-test-in-qemu.md).
