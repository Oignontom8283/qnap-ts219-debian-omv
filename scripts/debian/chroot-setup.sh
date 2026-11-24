#!/bin/sh
# Runs INSIDE the armel chroot (called by scripts/pc/container-build-rootfs.sh).
set -eux
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
. /tmp/build.env
F=/tmp/files

echo "$NAS_HOSTNAME" > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 %s\n::1 localhost ip6-localhost ip6-loopback\n' "$NAS_HOSTNAME" > /etc/hosts
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main
deb http://deb.debian.org/debian bookworm-updates main
deb http://security.debian.org/debian-security bookworm-security main
EOF
apt-get update

# 1. initramfs-tools FIRST, so its configuration is in place before the kernel package builds the initramfs.
#    busybox MUST be installed: without it the initramfs has no `rm` and Debian's mdadm scripts fail.
apt-get install -y --no-install-recommends initramfs-tools mdadm kmod busybox
sed -i 's/^MODULES=.*/MODULES=list/; s/^COMPRESS=.*/COMPRESS=gzip/' /etc/initramfs-tools/initramfs.conf
cp $F/initramfs-modules /etc/initramfs-tools/modules
install -m 0755 $F/local-bottom-subroot /etc/initramfs-tools/scripts/local-bottom/qnap-subroot
mkdir -p /etc/initramfs-tools/conf.d
echo 'BOOT_DEGRADED=true' > /etc/initramfs-tools/conf.d/mdadm-degraded
cat > /etc/mdadm/mdadm.conf <<EOF
MAILADDR root
HOMEHOST <ignore>
AUTO -all
ARRAY /dev/md0 metadata=0.90 UUID=$MD0_UUID
EOF

# 2. base system
apt-get install -y --no-install-recommends \
  systemd systemd-sysv systemd-resolved systemd-timesyncd udev dbus netbase \
  openssh-server iproute2 iputils-ping ethtool \
  e2fsprogs xz-utils u-boot-tools libubootenv-tool mtd-utils \
  smartmontools hdparm less nano curl ca-certificates procps sudo
# (qcontrol, the fan/LED daemon, is installed on the LIVE system - that is what was tested; see docs/07)

# 3. Debian kernel (this generates the initramfs using the configuration above).
#    systemd-resolved replaced /etc/resolv.conf by a dead symlink inside the chroot: restore the host's DNS.
rm -f /etc/resolv.conf; cp /tmp/resolv.host /etc/resolv.conf
apt-get update
apt-get install -y --no-install-recommends linux-image-marvell

# 4. configuration
echo root:"$(cat /tmp/rootpw)" | chpasswd
mkdir -p /etc/ssh/sshd_config.d
printf 'PermitRootLogin yes\n' > /etc/ssh/sshd_config.d/10-nas.conf      # tighten later, see docs/09
mkdir -p /etc/systemd/network
sed "s/@NAS_MAC@/$NAS_MAC/" $F/00-eth0.link.in > /etc/systemd/network/00-eth0.link
cp $F/10-eth0.network /etc/systemd/network/10-eth0.network
echo '/dev/md0 /media/md0 ext4 noatime,nofail 0 0' > /etc/fstab
printf '/dev/mtd4 0x0 0x1000 0x40000\n' > /etc/fw_env.config            # read-only use: Linux cannot write the env
install -m 0755 $F/qnap-boot-confirm /usr/local/sbin/qnap-boot-confirm
cp $F/qnap-boot-confirm.service /etc/systemd/system/qnap-boot-confirm.service
systemctl enable systemd-networkd systemd-resolved ssh systemd-timesyncd
# qnap-boot-confirm.service is enabled later, after the first successful boot (docs/07).
rm -f /etc/machine-id; : > /etc/machine-id
apt-get clean
rm -rf /var/lib/apt/lists/*
update-initramfs -u -k all
rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
ls -l /boot
