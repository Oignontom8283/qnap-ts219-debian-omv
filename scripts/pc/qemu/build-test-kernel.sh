#!/bin/sh
# Runs in an arm32v7 (armhf) container. Builds a GENERIC ARM kernel (QEMU "virt") + an initramfs that uses
# the SAME initramfs-tools scripts/config as the real one, so the RAID/bind-mount logic is really exercised.
# (The real marvell kernel cannot be emulated: QEMU has no Kirkwood machine.)
set -eux
export DEBIAN_FRONTEND=noninteractive
. /config/build.env
apt-get update -qq
apt-get install -y -qq --no-install-recommends linux-image-armmp initramfs-tools mdadm kmod busybox
sed -i 's/^MODULES=.*/MODULES=list/; s/^COMPRESS=.*/COMPRESS=gzip/' /etc/initramfs-tools/initramfs.conf
cp /scripts/debian/files/initramfs-modules /etc/initramfs-tools/modules
# virtio drivers for the emulated disks and NIC (the rootfs only has the *marvell* kernel's modules)
printf 'virtio\nvirtio_ring\nvirtio_mmio\nvirtio_pci\nvirtio_blk\nvirtio_net\n' >> /etc/initramfs-tools/modules
install -m 0755 /scripts/debian/files/local-bottom-subroot /etc/initramfs-tools/scripts/local-bottom/qnap-subroot
echo 'BOOT_DEGRADED=true' > /etc/initramfs-tools/conf.d/mdadm-degraded
cat > /etc/mdadm/mdadm.conf <<EOC
HOMEHOST <ignore>
AUTO -all
ARRAY /dev/md0 metadata=0.90 UUID=$MD0_UUID
EOC
KV=$(ls /lib/modules | head -1)
mkinitramfs -o /t/initrd-test.img "$KV"
cp /boot/vmlinuz-$KV /t/vmlinuz-test
ls -l /t
