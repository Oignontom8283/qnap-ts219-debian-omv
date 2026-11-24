#!/usr/bin/env python3
"""Create a user, a shared folder and an SMB share in OpenMediaVault through its RPC API (omv-rpc).
Run ON THE NAS as root, AFTER omv-install-armel.sh and after the "/" fstab line + sharerootfs plugin (docs/08).

usage: omv-create-share.py <smb_user> <smb_password> <share_name> <path_relative_to_/>
   e.g. omv-create-share.py nas 'a-long-password' Public media/md0/Public/

Notes learned the hard way:
 * New objects MUST use OMV's special "new object" UUID, not a random one (random -> "Failed to execute XPath query").
 * The user creation also sets the Samba password.
 * Applying the configuration (Config.applyChanges) is slow on this CPU and omv-rpc times out after ~60 s, but
   the deployment keeps running inside omv-engined: wait for /var/lib/openmediavault/dirtymodules.json to be [].
"""
import json, subprocess, sys

NEW = "fa4b1c66-ef79-11e5-87a0-0002b3a176b4"              # OMV_CONFIGOBJECT_NEW_UUID
ROOTFS_MNTENT = "79684322-3eac-11ea-a974-63a080abab18"    # fixed UUID used by openmediavault-sharerootfs

def rpc(service, method, params=None):
    args = ["omv-rpc", "-u", "admin", service, method] + ([json.dumps(params)] if params is not None else [])
    r = subprocess.run(args, capture_output=True, text=True)
    print(f"[{service}.{method}] rc={r.returncode}", (r.stderr.strip() or r.stdout.strip())[:200])
    return r.stdout

if len(sys.argv) != 5:
    sys.exit(__doc__)
user, pw, share_name, reldir = sys.argv[1:5]

rpc("UserMgmt", "setUser", {"name": user, "groups": ["users"], "shell": "/usr/sbin/nologin", "password": pw,
                            "email": "", "comment": "NAS user", "disallowusermod": False, "sshpubkeys": []})
out = rpc("ShareMgmt", "set", {"uuid": NEW, "name": share_name, "reldirpath": reldir, "comment": share_name,
                               "mntentref": ROOTFS_MNTENT, "mode": "775"})
share = json.loads(out)["uuid"]
rpc("ShareMgmt", "setPrivileges", {"uuid": share, "privileges": [{"type": "user", "name": user, "perms": 7}]})
settings = json.loads(rpc("SMB", "getSettings"))
settings["enable"] = True
settings.pop("uuid", None)
rpc("SMB", "setSettings", settings)
rpc("SMB", "setShare", {"uuid": NEW, "enable": True, "sharedfolderref": share, "comment": share_name, "guest": "no",
                        "readonly": False, "browseable": True, "recyclebin": False, "recyclemaxsize": 0,
                        "recyclemaxage": 0, "hidedotfiles": True, "inheritacls": True, "inheritpermissions": True,
                        "easupport": False, "storedosattributes": False, "hostsallow": "", "hostsdeny": "",
                        "audit": False, "timemachine": False, "extraoptions": ""})
print("Now apply: nohup omv-rpc -u admin Config applyChanges '{\"modules\":[],\"force\":false}' &   "
      "then wait until /var/lib/openmediavault/dirtymodules.json is []")
