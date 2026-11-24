#!/usr/bin/env python3
"""Build a new 256 KiB MTD4 image (U-Boot environment) from YOUR backup of mtd4. Writes nothing to the NAS.

usage: make-env.py <mtd4_backup.bin> <out.bin> <klba> <kcnt> <rlba> <rcnt>
   values in hex (as printed by compute-layout.py), e.g.  0x1ffac8 0x2000 0x201ac8 0x4000

Environment format (stock QNAP U-Boot 1.1.4): 4-byte little-endian CRC32 of the next 4092 bytes, then
"name=value\\0" entries, a terminating empty entry, padding (copied from the original), 4096 bytes in total;
the rest of the 256 KiB sector is preserved from the backup.

The script REFUSES to run unless the original CRC is valid and bootcmd/bootargs are the known stock values.
"""
import sys, zlib, struct

if len(sys.argv) != 7:
    sys.exit(__doc__)
src, dst, klba, kcnt, rlba, rcnt = sys.argv[1:7]
ENV_SIZE = 0x1000

d = open(src, "rb").read()
assert len(d) == 0x40000, "expected a 256 KiB mtd4 dump"
assert struct.unpack("<I", d[:4])[0] == zlib.crc32(d[4:ENV_SIZE]) & 0xFFFFFFFF, "original env CRC invalid: STOP"
body = d[4:ENV_SIZE]
end = body.index(b"\0\0")
pad = body[end + 2:end + 3]
env = {}
for e in body[:end].split(b"\0"):
    k, v = e.decode("ascii").split("=", 1)
    env[k] = v

assert env["bootargs"] == "console=ttyS0,115200 root=/dev/ram initrd=0xa00000,0x900000 ramdisk=34816", \
    "unexpected stock bootargs: adapt this script only if you understand why"
assert env["bootcmd"] == "uart1 0x68;cp.l 0xf8200000 0x800000 0x80000;cp.l 0xf8400000 0xa00000 0x240000;bootm 0x800000", \
    "unexpected stock bootcmd: adapt this script only if you understand why"

env.update({
    "klba": klba, "kcnt": kcnt, "rlba": rlba, "rcnt": rcnt,
    # exact stock boot sequence, kept as the fall-back (note: bootargs are set explicitly because debargs changes them)
    "stock": "setenv bootargs console=ttyS0,115200 root=/dev/ram initrd=0xa00000,0x900000 ramdisk=34816;"
             "uart1 0x68;cp.l 0xf8200000 0x800000 0x080000;cp.l 0xf8400000 0xa00000 0x240000;bootm 0x800000",
    # read kernel+initrd into RAM (device 0, then device 1 if it exists: harmless when absent)
    "debload": "ide reset;ide device 0;ide read 0x800000 $(klba) $(kcnt);ide read 0x4000000 $(rlba) $(rcnt);"
               "ide device 1;ide read 0x800000 $(klba) $(kcnt);ide read 0x4000000 $(rlba) $(rcnt)",
    # one-shot: zero the kernel header ON DISK (the image is already in RAM). Debian restores it when healthy.
    "debdis": "mw.b 0x2000000 0 200;ide device 0;ide write 0x2000000 $(klba) 1;"
              "ide device 1;ide write 0x2000000 $(klba) 1;ide device 0",
    "debargs": "setenv bootargs console=ttyS0,115200 root=/dev/md0 rootfstype=ext4 rw rootwait net.ifnames=0",
    "debboot": "run debload;run debdis;run debargs;uart1 0x68;bootm 0x800000 0x4000000;run stock",
    "bootcmd": "run debboot",
})
blob = b"".join(f"{k}={v}".encode("ascii") + b"\0" for k, v in env.items()) + b"\0"
assert len(blob) <= ENV_SIZE - 4, f"environment too large: {len(blob)}"
data = blob + pad * (ENV_SIZE - 4 - len(blob))
img = struct.pack("<I", zlib.crc32(data) & 0xFFFFFFFF) + data + d[ENV_SIZE:]
assert len(img) == 0x40000
open(dst, "wb").write(img)
print(f"ok: {dst}: env {len(blob)}/{ENV_SIZE - 4} bytes")
print("Now validate it offline with libubootenv (docs/04-uboot-notes.md) BEFORE copying it to the NAS.")
