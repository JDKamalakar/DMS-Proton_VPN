import json, shutil, subprocess, urllib.request, socket, re

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
    "api_unsupported": False,
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

def fetch_latest_release():
    # 1. Try GitHub releases redirect (no API token / 60 req rate limit)
    try:
        req = urllib.request.Request("https://github.com/YourDoritos/pVPN/releases/latest", headers={"User-Agent": "Mozilla/5.0"})
        opener = urllib.request.build_opener(urllib.request.HTTPRedirectHandler)
        with opener.open(req, timeout=4) as resp:
            m = re.search(r'/tag/([^/]+)', resp.geturl())
            if m:
                return m.group(1).strip()
    except Exception:
        pass

    # 2. Try Atom feed
    try:
        req = urllib.request.Request("https://github.com/YourDoritos/pVPN/releases.atom", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            xml = resp.read().decode("utf-8")
            m = re.search(r'/releases/tag/([^"\'\s<>]+)', xml)
            if m:
                return m.group(1).strip()
    except Exception:
        pass

    # 3. Fallback to API if not rate-limited
    try:
        req = urllib.request.Request("https://api.github.com/repos/YourDoritos/pVPN/releases/latest", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            d = json.loads(resp.read().decode())
            return (d.get("tag_name") or "").strip()
    except Exception:
        pass

    return ""

try:
    tag = fetch_latest_release()
    status["latest_version"] = tag
    if tag and status["installed_version"]:
        def parse_v(v):
            v = v.lstrip("v")
            return [int(x) for x in v.split(".") if x.isdigit()]
        status["has_update"] = (parse_v(tag) > parse_v(status["installed_version"]))
except Exception:
    pass

# Check if daemon has the API version override or if it gets 5003
try:
    env_out = subprocess.check_output(["systemctl", "show", "pvpnd", "-p", "Environment", "--no-pager"], stderr=subprocess.DEVNULL).decode()
    if "PVPN_APPVERSION" not in env_out:
        # Check if the unoverridden version 4.19.0 gets 5003 error
        probe_req = urllib.request.Request("https://vpn-api.proton.me/vpn/v2", headers={
            "User-Agent": "ProtonVPN/4.19.0 (Linux; go-pvpn)",
            "x-pm-appversion": "linux-vpn@4.19.0",
            "Content-Type": "application/json"
        })
        try:
            with urllib.request.urlopen(probe_req, timeout=3) as _:
                pass
        except urllib.error.HTTPError as e:
            if e.code == 422:
                body = e.read().decode("utf-8", errors="ignore")
                if "5003" in body:
                    status["api_unsupported"] = True
                    status["has_update"] = True
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
