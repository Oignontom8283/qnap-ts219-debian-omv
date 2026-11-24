# 04 — What this U-Boot can do (and how that was found)

No serial console was used. Capabilities were established from the **binary** of MTD0 (read from the backup)
and then confirmed by behaviour on the real unit.

## Method

```sh
strings -n 4 mtd0.uboot.bin > uboot_strings.txt     # then read it
```

Banner: `U-Boot 1.1.4 (Sep 20 2010 - 15:17:40) Marvell version: 3.5.3` (non-hush shell: no `if`, no `&&`).
Useful findings (confirmed by observation unless noted):

| Feature | Evidence |
|---|---|
| `ide reset / device / read / write / info` | `ide read` confirmed (kernel loaded); `ide write` confirmed (header zeroed on disk) |
| `run`, `setenv`, `saveenv`, `mw`, `cp`, `bootm` | in help strings; `run`, `mw.b`, `bootm` used successfully. `saveenv` worked in an early iteration (it rewrote the env) |
| `ext2load`, `fatload`, `usb`, `tftpboot` | in help strings (not needed here) |
| Reset-button recovery (`rcvr`, USB `/multiware.img`, `/flashware.img`, `/upgrade.me`, then network "Distress Beacon" TFTP) | strings only — **not tested** |
| `enaAutoRecovery=yes` in the stock env | read from env |
| `sflash protect <on|off>` and "Failed to set the write protection to ALL" | strings; explains why Linux cannot write the env |
| `ATAG_INITRD2` (0x54420005) next to `ATAG_CORE/MEM/CMDLINE` constants | found by scanning the binary for the 32-bit constants; absent: `ATAG_INITRD` (old) and `ATAG_SERIAL` |
| Built-in default env: stock `bootargs`/`bootcmd` | in strings (used if the env CRC is bad) |
| Commands continue after a failing command in a `;` chain | observed (QTS booted after a failed `bootm`) |

Scan for the ATAG constants:

```python
import struct
d = open("mtd0.uboot.bin","rb").read()
for name,v in {"CORE":0x54410001,"MEM":0x54410002,"INITRD2":0x54420005,"CMDLINE":0x54410009}.items():
    print(name, [hex(i) for i in range(0,len(d)-3,4) if d[i:i+4]==struct.pack("<I",v)])
```

## `ide` quirks observed

- U-Boot exposes **one** SATA disk as device 0. Which physical disk that is vs. Linux's `sda`/`sdb` is *not*
  stable between boots (Linux enumerates asynchronously and the names swapped between two boots). Therefore
  the boot area is written identically to **both** disks and the confirm script restores both headers.
- `ide device 1` did not change the device (no second disk visible); the extra reads/writes are harmless.
- `ide write addr blk# cnt` takes **absolute** sector numbers and hex numbers (like everything in U-Boot).
- `ide read` of 8192 + 16384 sectors takes a fraction of a second.

## The env block

See [02-backup.md](02-backup.md) for the format. Size: 4096 bytes at the start of MTD4. Reference stock env was
790 bytes; the v3 env is ≈1.45 KB. Tooling: [scripts/pc/make-env.py](../scripts/pc/make-env.py) builds a full
256 KiB image from your own `mtd4` backup and asserts the stock `bootcmd`/`bootargs` first. Validate any
generated image offline with libubootenv before writing it:

```sh
printf '/path/mtd4.new.bin 0x0 0x1000 0x40000\n' > fw_env.config
fw_printenv -c fw_env.config            # (package libubootenv-tool) must list every variable
```

(`fw_setenv -s script` expects a different file format than `name value` lines — use one
`fw_setenv name value` call per variable when scripting offline tests.)
