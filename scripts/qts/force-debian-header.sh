#!/bin/sh
# Run ON THE NAS (QTS). Restores the kernel image header so the NEXT boot starts Debian again
# (needed after a fall-back to QTS, because U-Boot zeroed it).
# usage: sh force-debian-header.sh <uImage.pad> <krel> <klba>
set -e
K=$1; KREL=$2; KLBA=$3
swapoff /dev/md2 2>/dev/null || true
dd if="$K" of=/dev/md2 bs=512 seek="$KREL" count=1 2>&1 | tail -1
sync; sync; echo 3 > /proc/sys/vm/drop_caches
for d in sda sdb; do printf "$d header md5: "; dd if=/dev/$d bs=512 skip="$KLBA" count=1 2>/dev/null | md5sum; done
echo "expected: $(dd if=$K bs=512 count=1 2>/dev/null | md5sum)"
