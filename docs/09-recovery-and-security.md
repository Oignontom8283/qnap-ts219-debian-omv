# 09 — Recovery, going back to QTS, and security

## Normal safety net (tested)

If Debian does not come up healthy (kernel hang, no network, initramfs failure, broken update…) the kernel header
on disk is still zeroed at the next boot, `bootm` fails, and U-Boot runs the stock boot command → **QTS boots**.
You only need to power-cycle the box (hold the power button to force off, then power on).

- QTS returns with its own DHCP lease (it was `…13` on the reference unit; Debian was `…14`).
- Then, from QTS, fix Debian (the rootfs is the directory `/share/MD0_DATA/debian`, all files accessible), and
  re-arm it with `scripts/qts/force-debian-header.sh` followed by a reboot.

## Deliberately going back to QTS

From Debian: `sh scripts/debian/force-qts.sh && systemctl reboot` (zeroes the header; `qnap-boot-confirm` will not
run in QTS, so QTS keeps booting until you restore the header).

## Reverting completely to the stock configuration

From QTS: write your **original** `mtd4` backup back with `scripts/qts/write-uboot-env.sh <original> <current-any>`
(or `cat mtd4.uboot-config.bin > /dev/mtdblock4; sync`) and verify with `md5sum`/`ubootcfg`. U-Boot then boots QTS
exactly as before. The kernel/initramfs bytes at the end of md2 are inert and are simply overwritten by swap use.

## If neither Debian nor QTS answers

1. Wait the full 3–4 minutes (QTS needs ~3 minutes, Debian 1–2.5).
2. The **IP may have changed**: scan the subnet for port 22 / a Debian banner, check `arp -a` for the NAS MAC.
3. Power-cycle. A zeroed header → QTS. If the env block itself were corrupted, U-Boot uses its built-in default
   environment, which also boots QTS.
4. Still nothing: this is the only case where you need U-Boot's reset-button recovery (hold *reset* while powering
   on → the stock U-Boot tries a USB stick image `/multiware.img` or `/flashware.img`, then a TFTP "Distress Beacon").
   **This path was never exercised during this project.** A 3.3 V UART on header CN1 (115200 8N1; pin 1 GND, 2 RX,
   4 TX; never connect VCC) gives you a U-Boot prompt as a last resort.

## Hard rules

- Never write MTD0 (U-Boot).
- Never run `fw_setenv`/flash tools from Debian to "fix" the environment: the chip is write-protected by U-Boot
  and the tools report success without changing anything (see [10](10-lessons-and-pitfalls.md)).

## Security posture

- **Debian 12 gets no further security updates for `armel`** (Debian 12 LTS does not include armel). Treat the NAS
  as an unpatched appliance: trusted LAN only, **no port forwarding of anything, including SSH with keys**
  (a key protects against password guessing, not against a future sshd/Samba/nginx vulnerability).
- Remote access: a VPN on your router (WireGuard/OpenVPN) so only the VPN endpoint is exposed.
- Keep untrusted devices (guests, IoT) on a separate network segment.
- The build leaves `PermitRootLogin yes` with both the key and the random password. After you are done you can
  restrict to key-only (`/etc/ssh/sshd_config.d/10-nas.conf`: `PermitRootLogin prohibit-password`,
  `PasswordAuthentication no`) — keep a copy of the private key; recovering without it means going through QTS.
- The OMV web UI is plain HTTP on port 80.
- Samba (4.17.12 as shipped): SMB1 disabled (`server min protocol = SMB2_02`), `map to guest = Never`,
  `ntlm auth = ntlmv2-only`, `lanman auth = No`, no printing, no AD DC. It still listens on all interfaces; you can
  add `hosts allow` and `smb encrypt = desired`. Not done on the reference unit.
- If you keep QTS as a fall-back, change its default password (`admin`) — or at least keep it off untrusted networks.
