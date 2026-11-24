#!/bin/sh
# Host driver for the simulation. usage (from repo root, after build.sh): sh scripts/pc/qemu-test.sh
# Then:  ssh -i secrets/<key> -p 2223 root@127.0.0.1   (the guest takes ~3-4 minutes to boot, emulated)
set -eu
. ./config.env
if command -v cygpath >/dev/null 2>&1; then HERE=$(cygpath -w "$PWD"); export MSYS_NO_PATHCONV=1; else HERE=$PWD; fi
docker run --privileged --rm tonistiigi/binfmt --install arm >/dev/null
docker volume create nastest >/dev/null
docker run --rm --platform linux/arm/v7 -v nastest:/t -v "$HERE/scripts:/scripts:ro" -v "$HERE/config.env:/config/build.env:ro" \
  arm32v7/debian:bookworm-slim sh /scripts/pc/qemu/build-test-kernel.sh
docker rm -f nasqemu >/dev/null 2>&1 || true
docker run -d --name nasqemu --privileged -v nastest:/t -v "$HERE/out:/o:ro" -v "$HERE/scripts:/scripts:ro" \
  -v "$HERE/config.env:/config/build.env:ro" -p 2223:2223 debian:bookworm-slim sh /scripts/pc/qemu/make-disks-and-run.sh
echo "QEMU running in container 'nasqemu'. Watch: docker logs -f nasqemu"
