import json, shutil, subprocess, urllib.request, socket

status = {
    "pvpn": bool(shutil.which("pvpn")),
    "pvpnctl": bool(shutil.which("pvpnctl")),
    "pvpnd": bool(shutil.which("pvpnd")),
    "curl": bool(shutil.which("curl")),
    "systemctl": bool(shutil.which("systemctl")),
    "nft": bool(shutil.which("nft")),
    "wg": bool(shutil.which("wg")),
    "installed_version": "",
    "latest_version": "",
    "has_update": False,
    "logged_in": False,
    "username": "",
    "plan_name": "",
    "daemon_running": False
}

try:
    out = subprocess.check_output(["pvpnctl", "version"], stderr=subprocess.DEVNULL, timeout=2).decode().strip()
    status["installed_version"] = out.split()[1] if len(out.split()) > 1 else out
except Exception:
    pass

try:
    req = urllib.request.Request("https://api.github.com/repos/YourDoritos/pVPN/releases/latest", headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=4) as resp:
        d = json.loads(resp.read().decode())
        tag = (d.get("tag_name") or "").strip()
        status["latest_version"] = tag
        if tag and status["installed_version"]:
            def parse_v(v):
                v = v.lstrip("v")
                return [int(x) for x in v.split(".") if x.isdigit()]
            status["has_update"] = (parse_v(tag) > parse_v(status["installed_version"]))
except Exception:
    pass

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect("/run/pvpn/pvpn.sock")
    s.sendall(json.dumps({"command": "status"}).encode() + b"\n")
    raw = b""
    while b"\n" not in raw:
        chunk = s.recv(4096)
        if not chunk: break
        raw += chunk
    s.close()
    res = json.loads(raw.decode().strip())
    if res.get("ok"):
        status["daemon_running"] = True
        data = res.get("data", {})
        state = (data.get("state") or "").lower()
        user = data.get("username") or ""
        status["logged_in"] = (state != "not_authenticated" and bool(user or state == "connected"))
        status["username"] = user
        status["plan_name"] = data.get("plan_name") or ""
except Exception:
    pass

print(json.dumps(status))
