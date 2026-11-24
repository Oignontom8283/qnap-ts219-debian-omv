#!/bin/sh
# After a reboot, tells you WHICH system answered: Debian (key login) or QTS (password login).
# usage: QTS_IP=<qts-ip> DEBIAN_IP=<debian-ip> SSH_KEY=secrets/nas_ed25519 QTS_PASSWORD=... sh poll-nas.sh [seconds]
# Debian usually gets a different DHCP lease than QTS did; if neither answers, scan the subnet for a Debian
# banner on port 22 (e.g. the python snippet in docs/07) and look the NAS MAC up with `arp -a`.
t0=$(date +%s)
printf '#!/bin/sh\necho "$QTS_PASSWORD"\n' > /tmp/.askpass.$$; chmod +x /tmp/.askpass.$$
while [ $(( $(date +%s) - t0 )) -lt ${1:-480} ]; do
  el=$(( $(date +%s) - t0 ))
  D=$(ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=4 root@"$DEBIAN_IP" 'echo DEBIAN-OK; uptime' 2>/dev/null | tr '\n' ' ')
  [ -n "$D" ] && { echo "t+${el}s => $D"; rm -f /tmp/.askpass.$$; exit 0; }
  Q=$(SSH_ASKPASS=/tmp/.askpass.$$ SSH_ASKPASS_REQUIRE=force DISPLAY=:0 ssh -o HostKeyAlgorithms=+ssh-rsa \
        -o PreferredAuthentications=password,keyboard-interactive -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=4 admin@"$QTS_IP" 'echo QTS-OK; uptime' 2>/dev/null | tr '\n' ' ')
  [ -n "$Q" ] && { echo "t+${el}s => $Q"; rm -f /tmp/.askpass.$$; exit 0; }
  sleep 8
done
rm -f /tmp/.askpass.$$; echo TIMEOUT; exit 1
