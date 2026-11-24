#!/bin/sh
# Run ON DEBIAN. Forces the NEXT boot to fall back to QTS (zeroes the kernel header, exactly like U-Boot does).
# usage: sh force-qts.sh   (reads KERNEL_REL_SECTOR from /etc/qnap-boot.conf), then reboot.
. /etc/qnap-boot.conf
for d in /dev/sda2 /dev/sdb2; do
  [ -b "$d" ] && dd if=/dev/zero of="$d" bs=512 seek="$KERNEL_REL_SECTOR" count=1 conv=notrunc 2>/dev/null
done
sync; echo "Header zeroed. Reboot now: the NAS will come back under QTS."
