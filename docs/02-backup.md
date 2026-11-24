# 02 — Back up the flash (mandatory)

The six MTD partitions are your only way back to a stock system. Do this first and keep the files **private**
(they contain proprietary QNAP code and your unit's identity — never commit or post them).

On the NAS (QTS), write to the data volume, then copy to your PC:

```sh
D=/share/MD0_DATA/flash-backup; mkdir -p $D && cd $D
cat /dev/mtdblock0 > mtd0.uboot.bin
cat /dev/mtdblock1 > mtd1.kernel.bin
cat /dev/mtdblock2 > mtd2.rootfs.bin
cat /dev/mtdblock3 > mtd3.rootfs2.bin
cat /dev/mtdblock4 > mtd4.uboot-config.bin
cat /dev/mtdblock5 > mtd5.nas-config.bin
ls -l; md5sum *.bin
```

Expected sizes in bytes: `524288, 2097152, 9437184, 3145728, 262144, 1310720`.

Copy to the PC (legacy scp protocol) and compare the checksums:

```sh
scp -O -o HostKeyAlgorithms=+ssh-rsa admin@<NAS_IP>:/share/MD0_DATA/flash-backup/*.bin .
md5sum *.bin     # must match the NAS-side list
```

Note: on the QTS 2.6.33 kernel, reading the *character* device `/dev/mtd4` fails
("No such device or address"). Use `/dev/mtdblockN` for reading. After a write + `sync` the block layer
cache is flushed, so a re-read really comes from the chip.

## Check that the U-Boot environment is what you think

`mtd4` holds the environment as: 4-byte little-endian CRC32 of the following 4092 bytes, then
`name=value\0` entries, an empty entry (`\0\0`), padded (here with `0x00`) up to **4096 bytes**; the rest of
the 256 KiB sector is `0xFF`. Verify on your dump:

```python
import zlib, struct
d = open("mtd4.uboot-config.bin","rb").read()
print(struct.unpack("<I", d[:4])[0] == zlib.crc32(d[4:0x1000]) & 0xFFFFFFFF)   # must print True
```

If this prints `False` for your unit, **stop**: your environment size/layout differs and
[scripts/pc/make-env.py](../scripts/pc/make-env.py) must not be used as is.

The reference unit's `bootcmd` was
`uart1 0x68;cp.l 0xf8200000 0x800000 0x80000;cp.l 0xf8400000 0xa00000 0x240000;bootm 0x800000`
(the script asserts this exact value before modifying anything).

Next: [03-boot-architecture.md](03-boot-architecture.md).
