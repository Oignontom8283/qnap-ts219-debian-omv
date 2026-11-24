#!/usr/bin/env python3
"""Pad uImage / uInitrd with zeros to a whole number of 512-byte sectors, so what is read back from the raw
disk can be compared with md5 directly.   usage: pad-images.py <uImage> <uInitrd>   -> *.pad files"""
import math, sys, hashlib
for src in sys.argv[1:]:
    d = open(src, "rb").read()
    n = math.ceil(len(d) / 512) * 512
    d += b"\0" * (n - len(d))
    open(src + ".pad", "wb").write(d)
    print(f"{src}.pad  {n} bytes = {n // 512} sectors  md5={hashlib.md5(d).hexdigest()}")
