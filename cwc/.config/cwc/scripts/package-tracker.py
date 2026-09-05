import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

CONFIG = os.path.expanduser("~/.config/cwc/packages.json")
CACHE = os.path.expanduser("~/.cache/package-tracker.json")
TOKEN_CACHE = os.path.expanduser("~/.cache/fedex-oauth.json")
TTL = 570

ICON = "󰏓"

CLASS_BY_CODE = {
    "DL": "green",
    "OD": "green",
    "IN": "yellow",
    "DE": "red",
    "SE": "red",
    "CA": "red",
    "RS": "red",
}
PRIORITY = {"red": 4, "yellow": 3, "green": 2, "transit": 1}

FEDEX_HOSTS = {
    "production": "https://apis.fedex.com",
    "sandbox": "https://apis-sandbox.fedex.com",
}


def load_config():
    try:
        with open(CONFIG) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def post_json(url, body, headers):
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def fedex_token(creds):
    try:
        with open(TOKEN_CACHE) as f:
            tok = json.load(f)
        if tok.get("host") == creds["host"] and tok.get("expires_at", 0) > time.time() + 60:
            return tok["access_token"]
    except (OSError, ValueError):
        pass
    body = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": creds["client_id"],
        "client_secret": creds["client_secret"],
    }).encode()
    data = post_json(creds["host"] + "/oauth/token", body,
                     {"Content-Type": "application/x-www-form-urlencoded"})
    tok = {
        "access_token": data["access_token"],
        "expires_at": time.time() + int(data.get("expires_in", 3600)),
        "host": creds["host"],
    }
    fd = os.open(TOKEN_CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(tok, f)
    return tok["access_token"]


def fedex_eta(tr):
    dates = {d.get("type"): d.get("dateTime") for d in tr.get("dateAndTimes") or []}
    raw = dates.get("ACTUAL_DELIVERY") or dates.get("ESTIMATED_DELIVERY")
    if not raw:
        window = (tr.get("estimatedDeliveryTimeWindow") or {}).get("window") or {}
        raw = window.get("ends")
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw).strftime("%a %b %d")
    except ValueError:
        return raw


def track_fedex(cfg, packages):
    creds = dict(cfg.get("fedex") or {})
    cid = (creds.get("client_id") or "").strip()
    if not cid or cid.startswith("PASTE"):
        return {p["tracking"]: {"class": "yellow", "status": "api creds missing", "eta": None, "loc": ""}
                for p in packages}
    creds["host"] = FEDEX_HOSTS.get(creds.get("environment", "production"), FEDEX_HOSTS["production"])
    token = fedex_token(creds)
    body = json.dumps({
        "includeDetailedScans": False,
        "trackingInfo": [{"trackingNumberInfo": {"trackingNumber": p["tracking"]}} for p in packages],
    }).encode()
    data = post_json(creds["host"] + "/track/v1/trackingnumbers", body, {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "x-locale": "en_US",
    })
    results = {}
    for ctr in (data.get("output") or {}).get("completeTrackResults") or []:
        tn = ctr.get("trackingNumber", "")
        tr = (ctr.get("trackResults") or [{}])[0]
        err = tr.get("error")
        if err:
            results[tn] = {"class": "red", "status": err.get("message", "lookup failed"),
                           "eta": None, "loc": ""}
            continue
        lsd = tr.get("latestStatusDetail") or {}
        code = lsd.get("derivedCode") or lsd.get("code") or ""
        scan = lsd.get("scanLocation") or {}
        loc = " ".join(x for x in [scan.get("city"), scan.get("stateOrProvinceCode")] if x)
        results[tn] = {
            "class": CLASS_BY_CODE.get(code, "transit"),
            "status": lsd.get("statusByLocale") or lsd.get("description") or "no status yet",
            "eta": fedex_eta(tr),
            "loc": loc,
        }
    return results


CARRIERS = {"fedex": track_fedex}


def click_url(cfg):
    pkgs = (cfg or {}).get("packages") or []
    if not pkgs:
        return None
    if pkgs[0].get("url"):
        return pkgs[0]["url"]
    nums = ",".join(p["tracking"] for p in pkgs if p.get("carrier", "fedex") == "fedex")
    return f"https://www.fedex.com/fedextrack/?trknbr={nums}" if nums else None


def build(cfg):
    pkgs = cfg.get("packages") or []
    results = {}
    for name, fn in CARRIERS.items():
        mine = [p for p in pkgs if p.get("carrier", "fedex") == name]
        if mine:
            results.update(fn(cfg, mine))
    lines = [f"PACKAGES :: {len(pkgs)} tracked"]
    worst = "transit"
    for p in pkgs:
        r = results.get(p["tracking"]) or {"class": "red", "status": "no result from api",
                                           "eta": None, "loc": ""}
        if PRIORITY[r["class"]] > PRIORITY[worst]:
            worst = r["class"]
        line = f"  {p.get('label', p['tracking'])}: {r['status']}"
        if r["loc"]:
            line += f" @ {r['loc']}"
        lines.append(line)
        detail = f"    {p['tracking']}"
        if r["eta"]:
            detail += f" · eta {r['eta']}"
        lines.append(detail)
    if any(r["status"] == "api creds missing" for r in results.values()):
        lines.append("  → developer.fedex.com creds go in ~/.config/cwc/packages.json")
    text = ICON if len(pkgs) == 1 else f"{ICON} {len(pkgs)}"
    return {"text": text, "tooltip": "\n".join(lines), "class": worst, "alt": worst}


def emit(data):
    sys.stdout.write(json.dumps(data) + "\n")


def cache_key(cfg):
    pkgs = [(p.get("carrier", "fedex"), p.get("tracking")) for p in cfg.get("packages") or []]
    fp = json.dumps([pkgs, sorted((cfg.get("fedex") or {}).keys())], sort_keys=True)
    return hashlib.sha1(fp.encode()).hexdigest()


def main():
    cfg = load_config()
    if not cfg or not cfg.get("packages"):
        emit({"text": ""})
        return

    if "--open" in sys.argv:
        url = click_url(cfg)
        if url:
            subprocess.Popen(["xdg-open", url], start_new_session=True)
        return

    key = cache_key(cfg)
    cached = None
    try:
        with open(CACHE) as f:
            wrapped = json.load(f)
        if wrapped.get("key") == key:
            cached = wrapped["emit"]
            if time.time() - os.path.getmtime(CACHE) < TTL:
                emit(cached)
                return
    except (OSError, ValueError, KeyError):
        pass

    try:
        data = build(cfg)
        with open(CACHE, "w") as f:
            json.dump({"key": key, "emit": data}, f)
        emit(data)
    except Exception as e:
        if cached:
            cached = dict(cached, tooltip=cached.get("tooltip", "") + "\n(cached — fetch failed)")
            emit(cached)
        else:
            msg = e.code if isinstance(e, urllib.error.HTTPError) else e
            emit({"text": ICON, "tooltip": f"PACKAGES :: api error ({msg})\ncheck ~/.config/cwc/packages.json",
                  "class": "red", "alt": "red"})


if __name__ == "__main__":
    main()
