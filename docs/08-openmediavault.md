# 08 — OpenMediaVault 7 on armel (manual install)

OMV's official installer rejects `armel` ("Unsupported architecture :: armel"; the maintainer has stated he will
not support it) — and OMV 8 drops 32-bit ARM entirely, so **OMV 7 on Debian 12 is the last possible version**.
However the OMV 7 package repository **does publish an `armel` index**
(`https://openmediavault.github.io/packages/dists/sandworm/main/binary-armel/Packages.gz`, ~30 packages: `openmediavault`,
`salt-minion`/`salt-common` 3006, `php-pam`, `wsdd-server`, `openmediavault-sharerootfs`, …), and everything else
comes from Debian. So the packages can simply be installed by hand.

> Idle memory afterwards: ~80 MB used of 512 MB. Docker-based plugins are out of the question on this box.

## 1. Install

[scripts/debian/omv-install-armel.sh](../scripts/debian/omv-install-armel.sh) (run as root on the NAS, under `nohup`):
adds a 1 GB swap file, the OMV signing key and `sandworm` repo, pre-seeds postfix ("No configuration"), simulates
the install (`apt-get -s`), then installs `openmediavault openmediavault-keyring postfix` with
`--no-install-recommends`. It took roughly 20–25 minutes here. Do not use OMV's `install` script: it also rewrites the network
configuration.

Check afterwards: `dpkg -l openmediavault`, `curl -I http://127.0.0.1/` (HTTP 200), `systemctl --failed`.
Samba/NFS/mail units are inactive until you configure something — that is normal. `openmediavault-beep-up.service`
fails (no PC speaker): `systemctl mask` it.

## 2. Web UI password

The default login is `admin` / `openmediavault`. Change it non-interactively (this is what `omv-firstaid` does):

```sh
omv-rpc -u admin UserMgmt setPasswordByContext '{"password":"<new long password>"}'
```

Verify (from another machine): a `POST http://<IP>/rpc.php` with `{"service":"Session","method":"login","params":{"username":"admin","password":"..."},"options":null}`
returns `authenticated: true`, and the old password returns "Incorrect username or password".

## 3. Sharing folders from the existing data volume

OMV expects to mount its own filesystems under `/srv/dev-disk-by-uuid-*`. Here the data volume (md0) already
carries the root (`/debian` is bind-mounted as `/`), so OMV cannot "mount" it again with its own options. The
workable approach is the **`openmediavault-sharerootfs`** plugin, which lets OMV create shared folders on the root
filesystem. Folders can then live in `/media/md0/...` (the data volume mounted by the initramfs).

The plugin's postinst looks for a `/` entry in `/etc/fstab` (there is none: the root is assembled by the
initramfs) and otherwise prints "No root filesystem has been found". Add one, then re-run the configuration:

```sh
apt-get install -y --no-install-recommends openmediavault-sharerootfs
sed -i '1i UUID=<UUID of md0 filesystem> / ext4 defaults,noatime 0 0' /etc/fstab      # blkid /dev/md0
systemctl daemon-reload
/var/lib/dpkg/info/openmediavault-sharerootfs.postinst configure
omv-confdbadm read conf.system.filesystem.mountpoint        # must list uuid 79684322-3eac-11ea-a974-63a080abab18
```

(the `/` line has pass `0`: no fsck of a mounted filesystem.)

## 4. Create a user + folder + SMB share from the command line (optional; the web UI can do it too)

```sh
python3 scripts/debian/omv-create-share.py nas '<long password>' Public media/md0/Public/
nohup omv-rpc -u admin Config applyChanges '{"modules":[],"force":false}' >/root/omv-apply.log 2>&1 &
# omv-rpc times out after ~60 s (it printed "Failed to read from socket") but the deployment continues in
# omv-engined. Wait until the dirty list is empty:
cat /var/lib/openmediavault/dirtymodules.json        # [] when done (several minutes)
systemctl is-active smbd
```

Gotchas documented in the script header (OMV's special "new object" UUID, privileges, etc.).

## 5. Test the share end to end

Locally: `apt-get install smbclient; smbclient //127.0.0.1/Public -U nas -c ls`.
From a PC without trusting the OS SMB client: Python `smbprotocol` (`pip install smbprotocol`):

```python
import smbclient, os, hashlib
smbclient.ClientConfig(username="nas", password="<password>")
p = r"\\<NAS_IP>\Public\t.bin"; d = os.urandom(20_000_000)
smbclient.open_file(p, "wb").write(d); print(hashlib.md5(smbclient.open_file(p, "rb").read()).hexdigest() == hashlib.md5(d).hexdigest())
smbclient.remove(p)
```

(Measured with that pure-Python single-thread client: ~11 MB/s write, ~19 MB/s read, integrity OK. A native client
is faster; laserbirdx reports 30–40 MB/s SMB writes on the TS-219P II — not measured here.)

## 6. Inherited permissions from the old QNAP data

Old QNAP netatalk leftovers (`.AppleDB`, `.AppleDouble`, `.AppleDesktop`, `Network Trash Folder`) are owned by
`root` with restrictive modes, so an SMB user cannot delete them: remove them as root over SSH. Check what they
contain first (they are Berkeley-DB index files, a few hundred KB).

Next: [09-recovery-and-security.md](09-recovery-and-security.md).
