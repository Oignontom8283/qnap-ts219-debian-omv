#!/bin/sh
# Run ON THE DEBIAN NAS as root. Installs OpenMediaVault 7 on armel by hand. The official install script refuses
# armel ("Unsupported architecture") and rewrites the network config; the OMV package repository, however,
# DOES publish an armel index (including salt-minion 3006, php-pam, wsdd-server), so a plain apt install works.
# Took roughly 20-25 min on the 1.6 GHz ARMv5 used here. Run it under nohup/screen; it needs ~1 GB of swap (see docs/08).
set -eux
export DEBIAN_FRONTEND=noninteractive
# 1 GB swap FILE on the data volume (md2 is NOT used as swap under Debian: it holds the boot zones)
if ! swapon --show | grep -q swapfile; then
  fallocate -l 1G /swapfile; chmod 600 /swapfile; mkswap /swapfile >/dev/null; swapon /swapfile
  grep -q swapfile /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
apt-get update
apt-get install -y --no-install-recommends gnupg wget
wget -q -O /tmp/omv.key https://openmediavault.github.io/packages/archive.key
gpg --show-keys /tmp/omv.key
gpg --dearmor --yes --output /usr/share/keyrings/openmediavault-archive-keyring.gpg /tmp/omv.key
echo "deb [signed-by=/usr/share/keyrings/openmediavault-archive-keyring.gpg] https://openmediavault.github.io/packages/ sandworm main" \
  > /etc/apt/sources.list.d/openmediavault.list
apt-get update
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
apt-get -s install openmediavault | tail -5            # dry run first: look for conflicts
apt-get -y --no-install-recommends -o Dpkg::Options::=--force-confold install openmediavault openmediavault-keyring postfix
# The OMV postinst runs `omv-confdbadm populate` and the first salt deployments. Afterwards:
systemctl mask openmediavault-beep-up.service || true   # fails on this box (no PC speaker); qcontrol already beeps
