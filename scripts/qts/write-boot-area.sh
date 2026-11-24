#!/bin/sh
# Run ON THE NAS (QTS). Writes the kernel and initramfs images into the boot zones at the END of md2 and
# verifies them on BOTH physical disks, reading the raw disks at the ABSOLUTE sectors U-Boot will use.
#
# usage: sh write-boot-area.sh <uImage.pad> <uInitrd.pad> <krel> <rrel> <klba> <rlba>
#   *.pad  : images padded to whole sectors (scripts/pc/pad-images.py)
#   krel/rrel : zone starts relative to md2 (compute-layout.py "relative sectors")
#   klba/rlba : the same, absolute decimal sectors (compute-layout.py "absolute LBA", decimal numbers)
#
# Why swapoff: QTS keeps swap on md2. The zones are at the END of md2, far from where swap gets used,
# but writing to an active swap device is still avoided.
# Why drop_caches: /dev/sdX has its own page cache; without it a read-back of a sector written through md2
# can return STALE data (a false failure that cost time during the original install).
set -e
K=$1; R=$2; KREL=$3; RREL=$4; KLBA=$5; RLBA=$6
[ -f "$K" ] && [ -f "$R" ] && [ -n "$RLBA" ] || { echo "usage: see header"; exit 1; }
KS=$(( $(ls -l "$K" | awk '{print $5}') / 512 )); RS=$(( $(ls -l "$R" | awk '{print $5}') / 512 ))
[ $(( KS * 512 )) -eq $(ls -l "$K" | awk '{print $5}') ] || { echo "$K is not padded to 512"; exit 1; }
KM=$(md5sum "$K" | cut -d' ' -f1); RM=$(md5sum "$R" | cut -d' ' -f1)
echo "md2 state (should show [UU], not resyncing):"; grep -A1 '^md2' /proc/mdstat
swapoff /dev/md2 2>/dev/null || true
dd if="$K" of=/dev/md2 bs=512 seek="$KREL" 2>&1 | tail -1
dd if="$R" of=/dev/md2 bs=512 seek="$RREL" 2>&1 | tail -1
sync; sync; echo 3 > /proc/sys/vm/drop_caches
ok=1
for d in sda sdb; do
  k=$(dd if=/dev/$d bs=512 skip="$KLBA" count="$KS" 2>/dev/null | md5sum | cut -d' ' -f1)
  r=$(dd if=/dev/$d bs=512 skip="$RLBA" count="$RS" 2>/dev/null | md5sum | cut -d' ' -f1)
  echo "$d kernel=$k initrd=$r"
  [ "$k" = "$KM" ] && [ "$r" = "$RM" ] || ok=0
done
echo "expected kernel=$KM initrd=$RM"
[ $ok = 1 ] && echo "BOOT AREA VERIFIED ON BOTH DISKS" || { echo "VERIFY FAILED - do not write the U-Boot env"; exit 2; }
