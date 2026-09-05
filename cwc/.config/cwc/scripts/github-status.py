import json
import os
import sys
import time
import urllib.request

URL = "https://www.githubstatus.com/api/v2/summary.json"
CACHE = os.path.expanduser("~/.cache/github-status.json")
TTL = 120

ICON = "󰊤"

INDICATOR_CLASS = {
    "none": "green",
    "minor": "yellow",
    "major": "red",
    "critical": "red",
}


def fetch():
    req = urllib.request.Request(URL, headers={"User-Agent": "waybar-ghstatus/1"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def parse(payload):
    indicator = (payload.get("status") or {}).get("indicator", "unknown")
    description = (payload.get("status") or {}).get("description", "Unknown")
    bad = []
    for c in payload.get("components", []) or []:
        status = c.get("status")
        if status and status != "operational":
            if c.get("group"):
                continue
            bad.append({"name": c.get("name", "?"), "status": status})
    return {
        "class": INDICATOR_CLASS.get(indicator, "red"),
        "description": description,
        "bad": bad,
    }


def emit(data, stale=False):
    if data["bad"]:
        lines = [f"GITHUB :: {data['description']}"]
        for c in data["bad"]:
            pretty = c["status"].replace("_", " ")
            lines.append(f"  {c['name']}: {pretty}")
        tip = "\n".join(lines)
    else:
        tip = f"GITHUB :: {data['description']}"
    if stale:
        tip += "\n(cached — fetch failed)"
    sys.stdout.write(json.dumps({
        "text": ICON,
        "tooltip": tip,
        "class": data["class"],
        "alt": data["class"],
    }) + "\n")


def load_cache():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_cache(data):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w") as f:
        json.dump(data, f)


def main():
    cached = load_cache()
    if cached:
        try:
            age = time.time() - os.path.getmtime(CACHE)
        except OSError:
            age = TTL + 1
        if age < TTL:
            emit(cached)
            return
    try:
        data = parse(fetch())
        save_cache(data)
        emit(data)
    except Exception:
        if cached:
            emit(cached, stale=True)
        else:
            emit({"class": "red", "description": "status api unreachable", "bad": []}, stale=True)


if __name__ == "__main__":
    main()
