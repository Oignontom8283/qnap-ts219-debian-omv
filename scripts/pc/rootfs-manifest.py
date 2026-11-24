#!/usr/bin/env python3
"""Verify that rootfs.tar was extracted intact on the NAS. QTS's BusyBox 1.01 md5sum has no "-c", so:

  1. on the PC:   rootfs-manifest.py make  out/rootfs.tar  manifest.md5
  2. on the NAS:  cd /share/MD0_DATA/debian && find . -type f | while read f; do md5sum "$f"; done > /tmp/nas.md5
                  (copy /tmp/nas.md5 back with scp -O)
  3. on the PC:   rootfs-manifest.py compare manifest.md5 nas.md5

Expected harmless differences: hard links appear as extra files on the NAS (e.g. usr/bin/perl, usr/bin/uncompress)
because the tar lists them as links, and names containing a backslash (systemd "\\x2d" units) are printed escaped
by md5sum. Anything under "different" is a real problem.
"""
import hashlib, sys, tarfile

def make(tar, out):
    n = 0
    with tarfile.open(tar) as t, open(out, "w", newline="\n", encoding="utf-8") as m:
        for ti in t:
            name = ti.name[2:] if ti.name.startswith("./") else ti.name
            if name and ti.isreg():
                h = hashlib.md5(); f = t.extractfile(ti)
                for chunk in iter(lambda: f.read(1 << 20), b""): h.update(chunk)
                m.write(f"{h.hexdigest()}  {name}\n"); n += 1
    print(n, "regular files")

def load(p):
    d = {}
    for l in open(p, encoding="utf-8", errors="replace"):
        l = l.rstrip("\n")
        if l:
            h, _, n = l.partition("  ")
            d[n[2:] if n.startswith("./") else n] = h
    return d

def compare(a, b):
    A, B = load(a), load(b)
    miss = [n for n in A if n not in B]; extra = [n for n in B if n not in A]
    diff = [n for n in A if n in B and A[n] != B[n]]
    print(f"expected {len(A)}, found {len(B)}; missing {len(miss)}, extra {len(extra)}, different {len(diff)}")
    for n in (diff + miss + extra)[:20]: print("  ", n)

if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "make": make(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "compare": compare(sys.argv[2], sys.argv[3])
    else: sys.exit(__doc__)
