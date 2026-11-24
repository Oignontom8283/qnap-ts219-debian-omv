#!/bin/sh
# Run ON THE NAS (QTS). Writes a prepared 256 KiB U-Boot environment image to mtd4, verifies it, and rolls back
# to your ORIGINAL backup if the read-back differs. Only run after write-boot-area.sh printed VERIFIED.
#
# usage: sh write-uboot-env.sh <new_mtd4.bin> <original_mtd4_backup.bin>
# Reading uses /dev/mtdblock4 (the char device /dev/mtd4 cannot be read on the QTS 2.6.33 kernel); after
# write + sync the block layer cache is flushed, so the read-back comes from the chip.
set -e
NEW=$1; ORIG=$2
[ -f "$NEW" ] && [ -f "$ORIG" ] || { echo "usage: see header"; exit 1; }
[ "$(ls -l $NEW | awk '{print $5}')" = 262144 ] && [ "$(ls -l $ORIG | awk '{print $5}')" = 262144 ] || { echo "files must be 262144 bytes"; exit 1; }
WANT=$(md5sum "$NEW" | cut -d' ' -f1); OLD=$(md5sum "$ORIG" | cut -d' ' -f1)
CUR=$(cat /dev/mtdblock4 | md5sum | cut -d' ' -f1)
echo "current mtd4 md5: $CUR   original backup: $OLD   new: $WANT"
if [ "$CUR" != "$OLD" ] && [ "$CUR" != "$WANT" ] && [ "$FORCE" != 1 ]; then
  echo "ABORT: mtd4 is neither your original backup nor the new image (re-run with FORCE=1 if you know why)"; exit 1
fi
cat "$NEW" > /dev/mtdblock4; sync; sync
GOT=$(cat /dev/mtdblock4 | md5sum | cut -d' ' -f1)
echo "read-back md5: $GOT"
if [ "$GOT" != "$WANT" ]; then
  echo "MISMATCH -> restoring the original"; cat "$ORIG" > /dev/mtdblock4; sync; sync
  echo "restored md5: $(cat /dev/mtdblock4 | md5sum | cut -d' ' -f1) (expected $OLD)"; exit 2
fi
echo "OK. QNAP's own parser sees:"
/sbin/ubootcfg -b 0 -o - -f /dev/mtdblock4 | grep -E '^(bootcmd|klba|kcnt|rlba|rcnt|debboot|debload|debdis)='
