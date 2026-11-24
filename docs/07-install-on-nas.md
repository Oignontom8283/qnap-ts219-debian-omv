# 07 — Installation on the NAS

Prerequisites: backups done and verified ([02](02-backup.md)); images built ([05](05-build-images.md)); QEMU test passed
([06](06-test-in-qemu.md)); `/proc/mdstat` shows `[UU]` everywhere and **no resync** (wait for it to finish).
Replace `<NAS_IP>` with the QTS address. QTS has no `rsync`/`sftp`: use `scp -O`.

All numbers below come from `compute-layout.py` for *your* disks.

## 1. Copy files to the data volume

```sh
ssh=" -o HostKeyAlgorithms=+ssh-rsa"
ssh $ssh admin@<NAS_IP> 'mkdir -p /share/MD0_DATA/debian-install'
scp -O $ssh out/uImage.pad out/uInitrd.pad out/mtd4.new.bin out/rootfs.tar mtd4-backup.bin \
    scripts/qts/*.sh admin@<NAS_IP>:/share/MD0_DATA/debian-install/
ssh $ssh admin@<NAS_IP> 'cd /share/MD0_DATA/debian-install && md5sum *.pad *.bin rootfs.tar'   # compare with the PC
```

## 2. Extract the Debian tree on the volume and verify it

QTS ships a real GNU `tar` (not BusyBox's), so permissions/hard links/symlinks are preserved:

```sh
ssh $ssh admin@<NAS_IP> 'cd /share/MD0_DATA && [ ! -e debian ] && mkdir debian && cd debian && tar -xpf ../debian-install/rootfs.tar --numeric-owner'
python scripts/pc/rootfs-manifest.py make out/rootfs.tar out/manifest.md5
ssh $ssh admin@<NAS_IP> 'cd /share/MD0_DATA/debian && find . -type f | while read f; do md5sum "$f"; done > /tmp/nas.md5; wc -l < /tmp/nas.md5'
scp -O $ssh admin@<NAS_IP>:/tmp/nas.md5 out/nas.md5
python scripts/pc/rootfs-manifest.py compare out/manifest.md5 out/nas.md5     # "different 0" is what matters
```

Then add the two small files the *running* Debian needs for the one-shot mechanism (use your `krel`):

```sh
scp -O $ssh out/uImage.hdr admin@<NAS_IP>:/share/MD0_DATA/debian/usr/local/share/qnap/uImage.hdr   # mkdir the dir first
ssh $ssh admin@<NAS_IP> 'echo KERNEL_REL_SECTOR=<krel> > /share/MD0_DATA/debian/etc/qnap-boot.conf'
```

(The first boot cannot use `qnap-boot-confirm` until these exist; create the directory with
`mkdir -p /share/MD0_DATA/debian/usr/local/share/qnap`.)

## 3. Write the boot zones (raw disk) and verify

```sh
ssh $ssh admin@<NAS_IP> 'cd /share/MD0_DATA/debian-install && sh write-boot-area.sh uImage.pad uInitrd.pad <krel> <rrel> <klba_decimal> <rlba_decimal>'
```

It must end with `BOOT AREA VERIFIED ON BOTH DISKS`. Do **not** continue otherwise.

## 4. Write the U-Boot environment (the only flash write)

```sh
ssh $ssh admin@<NAS_IP> 'cd /share/MD0_DATA/debian-install && sh write-uboot-env.sh mtd4.new.bin mtd4-backup.bin'
```

The script compares the current content with your backup first, writes, reads back, rolls back automatically
on a mismatch, and finally shows what QNAP's own `ubootcfg` parser reads (`bootcmd=run debboot` …).

## 5. Reboot into Debian

```sh
ssh $ssh admin@<NAS_IP> 'sync; /sbin/reboot'
```

Observed twice: the **first** `reboot` over SSH was silently ignored; check `uptime` and send it again.
Debian then needs 1–2.5 minutes. **It will probably have a different IP** than QTS had (DHCP lease memory):

```sh
python - <<'PY'
import socket, concurrent.futures as cf
def p(i):
    ip=f"192.168.1.{i}"          # adapt to your subnet
    try:
        s=socket.create_connection((ip,22),timeout=1.5); s.settimeout(2); b=s.recv(80).decode(errors="replace").strip(); s.close(); return ip,b
    except Exception: return None
print([r for r in cf.ThreadPoolExecutor(64).map(p,range(1,255)) if r])      # look for "Debian" in the banner
PY
arp -a | grep -i "<your MAC with dashes>"
```

If nothing answers anywhere for ~5 minutes, power-cycle the NAS (see [09](09-recovery-and-security.md)).

## 6. First checks on Debian

```sh
ssh -i secrets/nas_ed25519 root@<DEBIAN_IP>
uname -r; systemctl is-system-running; findmnt -no SOURCE,FSROOT,TARGET /      # /dev/md0[/debian]
cat /proc/mdstat; ls /media/md0                                                  # your old data is here
# U-Boot has zeroed the kernel header on ONE disk (which one varies). Let sync/cache settle first:
sync; echo 3 > /proc/sys/vm/drop_caches
for d in sda2 sdb2; do dd if=/dev/$d bs=512 skip=<krel> count=1 2>/dev/null | md5sum; done   # one should be md5 of 512 zero bytes
```

## 7. Confirm, enable the automatic confirmation, and test the loop

```sh
/usr/local/sbin/qnap-boot-confirm              # restores the header on both disks
systemctl enable qnap-boot-confirm.service     # from now on Debian re-confirms itself 60 s after a healthy boot
systemctl reboot                                # Debian must come back by itself (~1 min)
```

**Test the safety net on purpose** before trusting it:

```sh
sh scripts/debian/force-qts.sh && systemctl reboot       # zeroes the header; the box must come back as QTS
# ...then from QTS:
sh force-debian-header.sh uImage.pad <krel> <klba_decimal> && /sbin/reboot     # Debian again
```

## 8. Fan, LEDs, temperatures

The PIC that drives the fan and LEDs is on `/dev/ttyS1`. Without a daemon the fan keeps whatever U-Boot left.

```sh
apt-get install -y --no-install-recommends qcontrol && systemctl enable --now qcontrold
journalctl -u qcontrold -b | tail        # "temperature 30", fan steps high -> medium -> low -> silence
smartctl -A /dev/sda | grep -i temperature
```

`qcontrol` ships `ts219.lua` with hysteresis thresholds (silence <32 °C … full >65 °C). It reads the temperature
from the PIC and receives the buttons through `gpio_keys`.

Next: [08-openmediavault.md](08-openmediavault.md) (optional web UI).
