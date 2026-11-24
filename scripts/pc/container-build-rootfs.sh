#!/bin/sh
# Runs INSIDE a privileged debian:bookworm-slim (amd64) container. ARM code runs through binfmt/QEMU.
# Builds a Debian armel rootfs in /rootfs, then produces uImage / uInitrd / rootfs.tar in /out.
set -eu
. /config/build.env
R=/rootfs
SUITE=${DEBIAN_SUITE:-bookworm}

apt-get update -qq
apt-get install -y -qq --no-install-recommends debootstrap ca-certificates xz-utils u-boot-tools device-tree-compiler >/dev/null

rm -rf "$R"/* "$R"/.[!.]* 2>/dev/null || true
echo "== debootstrap stage 1 =="
debootstrap --foreign --arch=armel --variant=minbase "$SUITE" "$R" http://deb.debian.org/debian
echo "== debootstrap stage 2 (emulated) =="
chroot "$R" /debootstrap/debootstrap --second-stage

mkdir -p "$R/root/.ssh"; chmod 700 "$R/root/.ssh"
cp /secrets/key.pub "$R/root/.ssh/authorized_keys"; chmod 600 "$R/root/.ssh/authorized_keys"
cp /secrets/root_password.txt "$R/tmp/rootpw"
cp /config/build.env "$R/tmp/build.env"
cp /etc/resolv.conf "$R/tmp/resolv.host"          # systemd-resolved breaks the chroot's DNS later; keep a copy
cp /etc/resolv.conf "$R/etc/resolv.conf"
cp /scripts/debian/chroot-setup.sh "$R/tmp/chroot-setup.sh"
cp -r /scripts/debian/files "$R/tmp/files"

printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod +x "$R/usr/sbin/policy-rc.d"   # no service starts in chroot
mount -t proc proc "$R/proc"; mount --bind /dev "$R/dev"; mount -t sysfs sys "$R/sys"
echo "== configuring inside the chroot =="
chroot "$R" /bin/sh /tmp/chroot-setup.sh
umount "$R/proc" "$R/sys" "$R/dev" || true
rm -f "$R/usr/sbin/policy-rc.d" "$R/tmp/rootpw" "$R/tmp/resolv.host" "$R/tmp/build.env" "$R/tmp/chroot-setup.sh"
rm -rf "$R/tmp/files"

echo "== boot artifacts =="
mkdir -p /out
KV=$(ls "$R"/boot | sed -n 's/^vmlinuz-//p' | head -1)
echo "kernel: $KV"
cp "$R/boot/vmlinuz-$KV" /out/vmlinuz
cp "$R/boot/initrd.img-$KV" /out/initrd.img
cp "$R/usr/lib/linux-image-$KV/kirkwood-ts219-6282.dtb" /out/kirkwood-ts219-6282.dtb
echo "$KV" > /out/kernel-version
cat /out/vmlinuz /out/kirkwood-ts219-6282.dtb > /out/zImage.dtb
mkimage -A arm -O linux -T kernel  -C none -a 0x00008000 -e 0x00008000 -n "Debian $KV" -d /out/zImage.dtb /out/uImage
# IMPORTANT: ramdisk load address must NOT be 0 (U-Boot would memmove the data to address 0 over the kernel)
mkimage -A arm -O linux -T ramdisk -C none -a 0x01100000 -e 0x01100000 -n "initrd $KV" -d /out/initrd.img /out/uInitrd
mkimage -l /out/uImage; mkimage -l /out/uInitrd
# The 512-byte header is what U-Boot zeroes on disk and what qnap-boot-confirm restores later.
head -c 512 /out/uImage > /out/uImage.hdr

echo "== rootfs archive =="
tar -C "$R" -cpf /out/rootfs.tar --numeric-owner .
ls -l /out
echo BUILD-OK
