#!/bin/sh
# Run ON THE NAS (QTS, BusyBox 1.01 sh). Backs up the 6 SPI-NOR partitions and prints their sizes + md5.
# usage: sh backup-flash.sh [/share/MD0_DATA/flash-backup]
D=${1:-/share/MD0_DATA/flash-backup}
mkdir -p "$D" && cd "$D" || exit 1
i=0
for n in uboot kernel rootfs rootfs2 uboot-config nas-config; do
  cat /dev/mtdblock$i > mtd$i.$n.bin || { echo "read of mtd$i failed"; exit 1; }
  i=$((i+1))
done
ls -l; md5sum *.bin
echo "Expected sizes: 524288 2097152 9437184 3145728 262144 1310720. Copy them to your PC (scp -O) and keep them PRIVATE."
