#!/usr/bin/env python3
"""
claude-usage.py — claude /usage numbers for waybar.
hits the oauth usage endpoint anthropic uses internally for /usage. returns the
exact five_hour and seven_day utilization percentages — same data as `/usage`.

discovered via https://github.com/anthropics/claude-code/issues/13585.
auth: bearer token from ~/.claude/.credentials.json (refreshed by the cli).

emits the waybar custom-module json contract: {text, tooltip, class, alt}.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

URL = "https://api.anthropic.com/api/oauth/usage"
BETA = "oauth-2025-04-20"
CREDS = os.path.expanduser("~/.claude/.credentials.json")
CACHE = os.path.expanduser("~/.cache/claude-usage.json")
TTL = 60  # endpoint is cheap but we don't need sub-minute resolution

ICON = "󰧠"  # nf-md-brain — AI-thinking chip


def load_token():
    with open(CREDS) as f:
        creds = json.load(f)
    tok = (creds.get("claudeAiOauth") or {}).get("accessToken")
    if not tok:
        raise RuntimeError("no claudeAiOauth.accessToken in credentials.json")
    return tok


def fetch():
    req = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {load_token()}",
        "anthropic-beta": BETA,
        "User-Agent": "waybar-claude-usage/1",
    })
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def color_class(pct):
    # green <75, yellow 75–85, orange 85–90, red ≥90
    if pct < 75:
        return "green"
    if pct < 85:
        return "yellow"
    if pct < 90:
        return "orange"
    return "red"


def parse_reset(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def fmt_reset(s, now=None):
    """human-friendly 'resets in 2h15m' / 'in 3d 4h'."""
    dt = parse_reset(s)
    if not dt:
        return "?"
    now = now or datetime.now(timezone.utc)
    delta = (dt - now).total_seconds()
    if delta <= 0:
        return "any moment"
    days, rem = divmod(int(delta), 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    if days:
        return f"{days}d{hours:02d}h"
    if hours:
        return f"{hours}h{minutes:02d}m"
    return f"{minutes}m"


def util(window):
    if not isinstance(window, dict):
        return None
    return window.get("utilization")


def emit(payload, error=None, stale=False):
    five = util(payload.get("five_hour")) or 0
    seven = util(payload.get("seven_day")) or 0
    cls = color_class(five)
    five_reset = fmt_reset((payload.get("five_hour") or {}).get("resets_at"))
    seven_reset = fmt_reset((payload.get("seven_day") or {}).get("resets_at"))

    sonnet = util(payload.get("seven_day_sonnet"))
    opus = util(payload.get("seven_day_opus"))

    lines = [
        f"CLAUDE :: session {five:.0f}% · week {seven:.0f}%",
        f"  session: {five:.0f}% (resets in {five_reset})",
        f"  weekly:  {seven:.0f}% (resets in {seven_reset})",
    ]
    if sonnet is not None:
        lines.append(f"  sonnet:  {sonnet:.0f}%")
    if opus is not None:
        lines.append(f"  opus:    {opus:.0f}%")
    extra = payload.get("extra_usage") or {}
    if extra.get("is_enabled"):
        used = extra.get("used_credits") or 0
        cap = extra.get("monthly_limit")
        cap_s = f" / ${cap}" if cap else ""
        lines.append(f"  extra:   ${used:.2f}{cap_s} ({extra.get('currency','USD')})")
    if stale:
        lines.append(f"(cached — {error or 'fetch failed'})")
    elif error:
        lines.append(f"(error: {error})")

    sys.stdout.write(json.dumps({
        "text": ICON,
        "tooltip": "\n".join(lines),
        "class": cls,
        "alt": cls,
        "percentage": int(five),
    }) + "\n")


def load_cache():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_cache(payload):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"fetched_at": time.time(), "payload": payload}, f)
    os.replace(tmp, CACHE)


def main():
    now = time.time()
    cached = load_cache()
    if cached and (now - cached.get("fetched_at", 0)) < TTL:
        emit(cached["payload"])
        return
    try:
        payload = fetch()
        save_cache(payload)
        emit(payload)
    except urllib.error.HTTPError as e:
        msg = f"HTTP {e.code}"
        if e.code == 401:
            msg = "auth expired — run `claude` to refresh"
        if cached:
            emit(cached["payload"], error=msg, stale=True)
        else:
            emit({"five_hour": {"utilization": 0}}, error=msg, stale=True)
    except Exception as e:
        msg = str(e) or e.__class__.__name__
        if cached:
            emit(cached["payload"], error=msg, stale=True)
        else:
            emit({"five_hour": {"utilization": 0}}, error=msg, stale=True)


if __name__ == "__main__":
    main()
