#!/bin/sh
# Host-side driver: builds the Debian armel rootfs + kernel/initramfs/U-Boot images inside Docker.
# Requires: Docker (Linux containers) on a PC. Output goes to ./out (git-ignored).
#   usage: sh scripts/pc/build.sh          (run from the repository root, with config.env present)
set -eu
[ -f config.env ] || { echo "Create config.env from config.example.env first"; exit 1; }
. ./config.env
[ -f "$SSH_PUBKEY_FILE" ]     || { echo "Missing $SSH_PUBKEY_FILE (ssh-keygen -t ed25519 -f secrets/nas_ed25519)"; exit 1; }
[ -f "$ROOT_PASSWORD_FILE" ]  || { echo "Missing $ROOT_PASSWORD_FILE (one line, a long random password)"; exit 1; }
mkdir -p out

# Make the Docker VM able to run ARM (armel) binaries through QEMU user emulation. Idempotent.
docker run --privileged --rm tonistiigi/binfmt --install arm >/dev/null

# Convert Windows paths when running under Git Bash / MSYS
if command -v cygpath >/dev/null 2>&1; then HERE=$(cygpath -w "$PWD"); export MSYS_NO_PATHCONV=1; else HERE=$PWD; fi

docker volume create nasroot >/dev/null     # the rootfs is built in a Docker volume (NOT on NTFS: needs Unix perms)
docker run --rm --privileged \
  -v nasroot:/rootfs \
  -v "$HERE/scripts:/scripts:ro" \
  -v "$HERE/config.env:/config/build.env:ro" \
  -v "$HERE/$SSH_PUBKEY_FILE:/secrets/key.pub:ro" \
  -v "$HERE/$ROOT_PASSWORD_FILE:/secrets/root_password.txt:ro" \
  -v "$HERE/out:/out" \
  "debian:${DEBIAN_SUITE:-bookworm}-slim" sh /scripts/pc/container-build-rootfs.sh 2>&1 | tee out/build.log
echo "Done. Artifacts in ./out : uImage uInitrd rootfs.tar (never commit them)."
