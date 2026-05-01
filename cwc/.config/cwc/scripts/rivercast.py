#!/usr/bin/env python3
"""
rivercast.py — schuylkill river quality status for waybar.
scrapes phillyrivercast.org. red = the bacteria are partying. don't get in.
emits the waybar custom-module json contract: {text, tooltip, class, alt}.
"""
import html
import json
import os
import re
import sys
import time
import urllib.request

URL = "https://www.phillyrivercast.org/"
CACHE = os.path.expanduser("~/.cache/rivercast.json")
TTL = 1800  # site updates daily; 30min cache is plenty

ICON = "\U000f0608"  # nf-md-rowing — boathouse row energy


def fetch():
    req = urllib.request.Request(URL, headers={"User-Agent": "waybar-rivercast/1"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return r.read().decode("utf-8", "replace")


def parse(page):
    m = re.search(r'id="spanRating"[^>]*>\s*([A-Za-z]+)', page)
    status = m.group(1).lower() if m else "unknown"
    if status not in {"red", "yellow", "green"}:
        status = "unknown"

    m = re.search(
        r'<span class="pe-2">([^<]+)</span>\s*<span class="text-nowrap">([^<]+)</span>',
        page,
    )
    measured = f"{m.group(1)} {m.group(2)}" if m else "unknown"

    m = re.search(r'<div class="col-6">\s*(\d+\s*&deg;F[^<]*)', page)
    temp = html.unescape(re.sub(r"\s+", " ", m.group(1)).strip()) if m else "?"

    m = re.search(r'<div class="col-6">\s*([\d,]+\s*cfs[^<]*)', page)
    flow = re.sub(r"\s+", " ", m.group(1)).strip() if m else "?"

    return {"status": status, "measured": measured, "temp": temp, "flow": flow}


def emit(data, stale=False):
    tip = (
        f"PHILLY RIVERCAST :: {data['status'].upper()}\n"
        f"water: {data['temp']}\n"
        f"flow:  {data['flow']}\n"
        f"taken: {data['measured']}"
    )
    if stale:
        tip += "\n(cached — fetch failed)"
    sys.stdout.write(json.dumps({
        "text": ICON,
        "tooltip": tip,
        "class": data["status"],
        "alt": data["status"],
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
            emit({"status": "unknown", "measured": "?", "temp": "?", "flow": "?"}, stale=True)


if __name__ == "__main__":
    main()
