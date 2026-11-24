#!/bin/sh
# Runs in a privileged amd64 container. Creates two disk images holding a RAID 1 (metadata 0.90, same UUID as
# your NAS) whose ext4 filesystem contains /debian = your rootfs.tar, then boots them in QEMU.
set -eux
export DEBIAN_FRONTEND=noninteractive
. /config/build.env
apt-get update -qq
apt-get install -y -qq --no-install-recommends mdadm e2fsprogs fdisk util-linux qemu-system-arm tar >/dev/null
cd /t
# remove leftovers of a previous run (md/loop devices live in the Docker VM kernel and survive containers!)
mdadm --stop /dev/md0 2>/dev/null || true
for l in $(losetup -a | grep -E '/t/d[12]\.img|/d[12]\.img' | cut -d: -f1); do losetup -d "$l" || true; done
rm -f d1.img d2.img
for d in d1 d2; do
  truncate -s 2300M $d.img
  printf 'label: dos\n,2048,83\n,2048,83\n,,83\n' | sfdisk -q $d.img
done
OFF=$((6144*512)); LIM=$(( (2300*1024*1024) - OFF ))
L1=$(losetup -f --show -o $OFF --sizelimit $LIM d1.img); L2=$(losetup -f --show -o $OFF --sizelimit $LIM d2.img)
mdadm --create /dev/md0 --run --metadata=0.90 --level=1 --raid-devices=2 --uuid=$MD0_UUID $L1 $L2
mkfs.ext4 -q /dev/md0
mkdir -p /mnt/md0 && mount /dev/md0 /mnt/md0
mkdir /mnt/md0/debian && tar -xpf /o/rootfs.tar -C /mnt/md0/debian --numeric-owner
mkdir -p /mnt/md0/Share && echo existing-data > /mnt/md0/Share/test.txt     # proves the data volume stays visible
sync; umount /mnt/md0; mdadm --stop /dev/md0; losetup -d $L1 $L2
echo "== disks ready =="
exec sh /scripts/pc/qemu/run-qemu.sh
