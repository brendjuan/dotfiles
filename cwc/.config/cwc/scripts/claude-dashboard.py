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

TEAL = "\033[38;2;0;255;180m"
RED = "\033[38;2;255;0;80m"
AMBER = "\033[38;2;255;85;0m"
YELLOW = "\033[38;2;255;200;0m"
DIM = "\033[38;2;0;180;130m"
GHOST = "\033[38;2;0;120;90m"
BOLD = "\033[1m"
RESET = "\033[0m"


def load_token():
    with open(CREDS) as f:
        return json.load(f)["claudeAiOauth"]["accessToken"]


def fetch():
    req = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {load_token()}",
        "anthropic-beta": BETA,
        "User-Agent": "claude-dashboard/1",
    })
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def color_for(pct):
    if pct is None:
        return GHOST
    if pct < 75:
        return TEAL
    if pct < 85:
        return YELLOW
    if pct < 90:
        return AMBER
    return RED


def bar(pct, width=44):
    if pct is None:
        return f"{GHOST}{'·' * width}{RESET}"
    pct = max(0.0, min(100.0, pct))
    filled = int(round(width * pct / 100))
    col = color_for(pct)
    return f"{col}{'█' * filled}{GHOST}{'░' * (width - filled)}{RESET}"


def parse_reset(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def fmt_reset(s, now=None):
    dt = parse_reset(s)
    if not dt:
        return "—"
    now = now or datetime.now(timezone.utc)
    delta = (dt - now).total_seconds()
    if delta <= 0:
        return "any moment"
    days, rem = divmod(int(delta), 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    abs_local = dt.astimezone().strftime("%a %H:%M")
    if days:
        return f"in {days}d {hours}h  ({abs_local})"
    if hours:
        return f"in {hours}h {minutes:02d}m  ({abs_local})"
    return f"in {minutes}m  ({abs_local})"


def section(title):
    print(f"\n{BOLD}{RED}━━ {title} ━━{RESET}")


def render_window(label, window, indent=2):
    if window is None:
        print(f"{' ' * indent}{DIM}{label:<22}{RESET} {GHOST}—  (window not active){RESET}")
        return
    util = window.get("utilization")
    reset = window.get("resets_at")
    if util is None:
        pct_s = f"{GHOST}  —{RESET}"
    else:
        pct_s = f"{color_for(util)}{BOLD}{util:5.0f}%{RESET}"
    print(f"{' ' * indent}{DIM}{label:<22}{RESET} {bar(util)} {pct_s}")
    if reset:
        print(f"{' ' * (indent + 24)}{DIM}resets {fmt_reset(reset)}{RESET}")


def render(payload, source="live"):
    print(f"{BOLD}{TEAL}╔══ CLAUDE CODE :: USAGE INTELLIGENCE BRIEFING ═══════════════════════════╗{RESET}")
    src_color = TEAL if source == "live" else AMBER
    print(f"{DIM}  {datetime.now().strftime('%a %b %d %H:%M:%S')} · "
          f"{src_color}{source}{DIM} · GET /api/oauth/usage{RESET}")

    section("PRIMARY QUOTA")
    render_window("session (5h)", payload.get("five_hour"))
    render_window("weekly (7d)", payload.get("seven_day"))

    section("PER-MODEL  (last 7d)")
    render_window("opus", payload.get("seven_day_opus"))
    render_window("sonnet", payload.get("seven_day_sonnet"))

    other_keys = [
        ("seven_day_oauth_apps", "oauth apps (7d)"),
        ("seven_day_cowork", "cowork (7d)"),
        ("seven_day_omelette", "omelette (7d)"),
        ("tangelo", "tangelo"),
        ("iguana_necktie", "iguana_necktie"),
        ("omelette_promotional", "omelette promo"),
    ]
    other_active = [(k, l) for k, l in other_keys if payload.get(k) is not None]
    if other_active:
        section("OTHER WINDOWS")
        for key, label in other_active:
            render_window(label, payload.get(key))

    extra = payload.get("extra_usage")
    if extra:
        section("EXTRA USAGE  (overage credits)")
        on = extra.get("is_enabled")
        used = extra.get("used_credits") or 0
        cap = extra.get("monthly_limit")
        cur = extra.get("currency") or "USD"
        util = extra.get("utilization")
        state = f"{TEAL}enabled{RESET}" if on else f"{GHOST}disabled{RESET}"
        cap_s = f" / {cap} {cur}" if cap else f" {cur} (no cap)"
        print(f"  {DIM}status:{RESET}  {state}")
        print(f"  {DIM}spent:{RESET}   {used:.2f}{cap_s}")
        if util is not None:
            print(f"  {DIM}cap util:{RESET} {color_for(util)}{util:.1f}%{RESET}  {bar(util)}")

    print(f"\n{GHOST}  enter to close · numbers come straight from anthropic — no local approx{RESET}")


def main():
    payload = None
    source = "live"
    try:
        payload = fetch()
        try:
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            with open(CACHE, "w") as f:
                json.dump({"fetched_at": time.time(), "payload": payload}, f)
        except OSError:
            pass
    except urllib.error.HTTPError as e:
        msg = f"HTTP {e.code}" + (" — run `claude` to refresh auth" if e.code == 401 else "")
        source = f"cached (fetch failed: {msg})"
    except Exception as e:
        source = f"cached (fetch failed: {e})"

    if payload is None:
        try:
            with open(CACHE) as f:
                payload = json.load(f)["payload"]
        except (OSError, ValueError, KeyError):
            print(f"{RED}no live data and no cache available.{RESET}", file=sys.stderr)
            print(f"{DIM}check ~/.claude/.credentials.json and run `claude` once to refresh.{RESET}",
                  file=sys.stderr)
            sys.exit(1)

    render(payload, source=source)

    if sys.stdin.isatty():
        try:
            sys.stdout.write(f"{DIM}  [enter to close] {RESET}")
            sys.stdout.flush()
            sys.stdin.readline()
        except (KeyboardInterrupt, EOFError):
            pass


if __name__ == "__main__":
    main()
