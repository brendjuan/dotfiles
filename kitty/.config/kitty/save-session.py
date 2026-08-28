#!/usr/bin/env python3
"""Snapshot running kitty instances (tabs, layouts, cwds) into a session file.

Run by kitty-save-session.timer; resume-session.sh reopens the snapshot.
Windows that were running claude relaunch as `claude --continue`.
"""

import glob
import json
import os
import shlex
import stat
import subprocess
import tempfile

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "kitty"
)
SESSION_FILE = os.path.join(STATE_DIR, "last-session.conf")


def list_os_windows(sock):
    try:
        out = subprocess.run(
            ["kitten", "@", "--to", f"unix:{sock}", "ls"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if out.returncode != 0:
            return []
        return json.loads(out.stdout)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []


def window_lines(window):
    cwd = window.get("cwd") or os.path.expanduser("~")
    argv = []
    for proc in window.get("foreground_processes") or []:
        cmdline = proc.get("cmdline") or []
        if any(os.path.basename(arg) == "claude" for arg in cmdline[:2]):
            cwd = proc.get("cwd") or cwd
            argv = ["claude", "--continue"]
            break
    lines = [f"cd {cwd}"]
    if argv:
        lines.append("launch " + " ".join(shlex.quote(arg) for arg in argv))
    else:
        lines.append("launch")
    return lines


def main():
    os_window_chunks = []
    for sock in sorted(glob.glob("/tmp/kitty-*")):
        try:
            if not stat.S_ISSOCK(os.stat(sock).st_mode):
                continue
        except OSError:
            continue
        for os_window in list_os_windows(sock):
            lines = []
            for tab in os_window.get("tabs") or []:
                lines.append("new_tab")
                if tab.get("layout"):
                    lines.append(f"layout {tab['layout']}")
                for window in tab.get("windows") or []:
                    lines.extend(window_lines(window))
            if lines:
                os_window_chunks.append(lines)

    # No kitty running (e.g. right after boot): keep the last good snapshot.
    if not os_window_chunks:
        return

    out = []
    for i, chunk in enumerate(os_window_chunks):
        if i:
            out.append("new_os_window")
        out.extend(chunk)

    os.makedirs(STATE_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".last-session-")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(out) + "\n")
        os.replace(tmp, SESSION_FILE)
    except BaseException:
        os.unlink(tmp)
        raise


if __name__ == "__main__":
    main()
