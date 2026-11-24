#!/bin/sh
# Boots the two disk images in QEMU. Needs  -M virt,highmem=off  (the generic armhf kernel's PCI host fails
# otherwise: "pci-host-generic: probe failed with error -16", no disks visible).
command -v qemu-system-arm >/dev/null || { apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq --no-install-recommends qemu-system-arm >/dev/null 2>&1; }
exec timeout ${QEMU_TIMEOUT:-900} qemu-system-arm -M virt,highmem=off -cpu cortex-a15 -m 512 -nographic -no-reboot \
  -kernel /t/vmlinuz-test -initrd /t/initrd-test.img \
  -append "console=ttyAMA0 root=/dev/md0 rootfstype=ext4 rw rootwait net.ifnames=0 ${EXTRA_CMDLINE:-}" \
  -drive file=/t/d1.img,if=virtio,format=raw -drive file=/t/d2.img,if=virtio,format=raw \
  -netdev user,id=n0,hostfwd=tcp:0.0.0.0:2223-:22 -device virtio-net-pci,netdev=n0,romfile=
