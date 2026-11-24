#!/usr/bin/env python3
"""Compute where the Debian boot zones go, from YOUR disk geometry. Prints everything needed by later steps.

usage: compute-layout.py <PART2_START_SECTOR> <MD2_SECTORS> <uImage_file> <uInitrd_file>

 PART2_START_SECTOR : start sector of partition 2 (fdisk -lu /dev/sda, column Start)
 MD2_SECTORS        : size of the md2 array in 512-byte sectors (/proc/mdstat blocks * 2)

Layout (both zones sit at the END of md2, because QTS re-enables swap on md2 and swap fills from the start):

   md2:  [ ........ swap area ........ | kernel zone (4 MiB) | initrd zone (8 MiB) ]  <- end of md2

Zones are fixed-size (U-Boot reads a fixed number of sectors); the images must fit inside them.
Nothing is written by this script.
"""
import math, os, sys

KZONE = 8192      # sectors = 4 MiB   (U-Boot kcnt)
RZONE = 16384     # sectors = 8 MiB   (U-Boot rcnt)

if len(sys.argv) != 5:
    sys.exit(__doc__)
p2, md2 = int(sys.argv[1]), int(sys.argv[2])
ks = math.ceil(os.path.getsize(sys.argv[3]) / 512)
rs = math.ceil(os.path.getsize(sys.argv[4]) / 512)
if ks > KZONE: sys.exit(f"kernel image too big: {ks} sectors > {KZONE}")
if rs > RZONE: sys.exit(f"initrd image too big: {rs} sectors > {RZONE}")

krel = md2 - KZONE - RZONE           # kernel zone start, relative to partition 2 / md2
rrel = krel + KZONE                  # initrd zone start
assert rrel + RZONE == md2
print(f"images            : kernel {ks} sectors, initrd {rs} sectors (zones: {KZONE} / {RZONE})")
print(f"relative sectors  : kernel zone = {krel}, initrd zone = {rrel}    (use as dd seek= on /dev/md2, bs=512)")
print(f"absolute LBA      : klba = {p2 + krel} ({hex(p2 + krel)}), rlba = {p2 + rrel} ({hex(p2 + rrel)})  (U-Boot, hex)")
print(f"U-Boot counts     : kcnt = {hex(KZONE)}, rcnt = {hex(RZONE)}")
print()
print("make-env.py arguments:  ", hex(p2 + krel), hex(KZONE), hex(p2 + rrel), hex(RZONE))
print(f"/etc/qnap-boot.conf   :  KERNEL_REL_SECTOR={krel}")
