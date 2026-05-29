#!/usr/bin/env python3
"""Fullscreen terminal GPS fix indicator.

Subscribes to a sensor_msgs/NavSatFix topic and paints the entire terminal
green (FIX) or red (NO FIX). The footer shows the SBG INS solution mode,
the raw GPS pos-type, and the number of satellites used in the solution.

If no NavSatFix publisher is present, the screen reads "NO GPS TOPIC" on
red.

Usage:
    python3 gps-fix.py
    python3 gps-fix.py --gps-topic /ins/imu/nav_sat_fix
"""

import argparse
import shutil
import signal
import sys
import threading
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from sbg_driver.msg import SbgEkfNav, SbgGpsPos
from sensor_msgs.msg import NavSatFix, NavSatStatus


# SbgEkfStatus.solution_mode (see sbg_driver/msg/SbgEkfStatus.msg).
_SOLUTION_MODE_LABELS = {
    0: "UNINIT",
    1: "VGYRO",
    2: "AHRS",
    3: "NAV_VEL",
    4: "NAV_POS",
}

# SbgGpsPosStatus.type (see sbg_driver/msg/SbgGpsPosStatus.msg).
_GPS_POS_TYPE_LABELS = {
    0: "NO_SOL",
    1: "UNKNOWN",
    2: "SINGLE",
    3: "PSRDIFF",
    4: "SBAS",
    5: "OMNI",
    6: "RTK_FLT",
    7: "RTK_INT",
    8: "PPP_FLT",
    9: "PPP_INT",
    10: "FIXED",
}

# SbgGpsPos.num_sv_used uses 0xFF as the "not available" sentinel.
_NUM_SV_NA = 0xFF


# ANSI escape sequences
RESET = "\033[0m"
HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"
CLEAR = "\033[2J"
HOME = "\033[H"
BG_GREEN = "\033[42m"
BG_RED = "\033[41m"
FG_WHITE = "\033[97m"
BOLD = "\033[1m"


# 5-row block font, rendered with full-block characters. Each glyph is
# returned as a list of 5 equal-width strings.
_GLYPHS = {
    "F": [
        "█████",
        "█    ",
        "████ ",
        "█    ",
        "█    ",
    ],
    "I": [
        "█████",
        "  █  ",
        "  █  ",
        "  █  ",
        "█████",
    ],
    "X": [
        "█   █",
        " █ █ ",
        "  █  ",
        " █ █ ",
        "█   █",
    ],
    "N": [
        "█   █",
        "██  █",
        "█ █ █",
        "█  ██",
        "█   █",
    ],
    "O": [
        "█████",
        "█   █",
        "█   █",
        "█   █",
        "█████",
    ],
    "P": [
        "████ ",
        "█   █",
        "████ ",
        "█    ",
        "█    ",
    ],
    "G": [
        "█████",
        "█    ",
        "█  ██",
        "█   █",
        "█████",
    ],
    "S": [
        "█████",
        "█    ",
        "█████",
        "    █",
        "█████",
    ],
    "T": [
        "█████",
        "  █  ",
        "  █  ",
        "  █  ",
        "  █  ",
    ],
    "C": [
        "█████",
        "█    ",
        "█    ",
        "█    ",
        "█████",
    ],
    " ": [
        "   ",
        "   ",
        "   ",
        "   ",
        "   ",
    ],
}


def render_block_text(text: str) -> list[str]:
    """Render uppercase ASCII text into a list of 5 strings (block letters)."""
    text = text.upper()
    rows = ["", "", "", "", ""]
    for i, ch in enumerate(text):
        glyph = _GLYPHS.get(ch, _GLYPHS[" "])
        for r in range(5):
            if i > 0:
                rows[r] += " "
            rows[r] += glyph[r]
    return rows


class GpsFixNode(Node):
    def __init__(self, gps_topic: str, ekf_nav_topic: str, gps_pos_topic: str):
        super().__init__("gps_fix_monitor")

        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )

        self.gps_topic = gps_topic

        self.lock = threading.Lock()
        self.gps_status: int | None = None  # NavSatStatus.status
        self.last_gps_time: float | None = None
        self.solution_mode: int | None = None  # SbgEkfStatus.solution_mode
        self.last_ekf_nav_time: float | None = None
        self.gps_pos_type: int | None = None  # SbgGpsPosStatus.type
        self.num_sv_used: int | None = None  # SbgGpsPos.num_sv_used
        self.last_gps_pos_time: float | None = None

        self.create_subscription(NavSatFix, gps_topic, self._on_gps, qos)
        self.create_subscription(SbgEkfNav, ekf_nav_topic, self._on_ekf_nav, qos)
        self.create_subscription(SbgGpsPos, gps_pos_topic, self._on_gps_pos, qos)

    def _on_gps(self, msg: NavSatFix) -> None:
        with self.lock:
            self.gps_status = msg.status.status
            self.last_gps_time = time.monotonic()

    def _on_ekf_nav(self, msg: SbgEkfNav) -> None:
        with self.lock:
            self.solution_mode = msg.status.solution_mode
            self.last_ekf_nav_time = time.monotonic()

    def _on_gps_pos(self, msg: SbgGpsPos) -> None:
        with self.lock:
            self.gps_pos_type = msg.status.type
            self.num_sv_used = msg.num_sv_used
            self.last_gps_pos_time = time.monotonic()

    def has_gps_publisher(self) -> bool:
        return self.count_publishers(self.gps_topic) > 0

    def snapshot(self) -> dict:
        with self.lock:
            return {
                "gps_status": self.gps_status,
                "last_gps_time": self.last_gps_time,
                "solution_mode": self.solution_mode,
                "last_ekf_nav_time": self.last_ekf_nav_time,
                "gps_pos_type": self.gps_pos_type,
                "num_sv_used": self.num_sv_used,
                "last_gps_pos_time": self.last_gps_pos_time,
                "has_publisher": self.has_gps_publisher(),
            }


def has_fix(status: int | None) -> bool:
    return status is not None and status != NavSatStatus.STATUS_NO_FIX


def _fresh(now: float, last: float | None, stale_after: float) -> bool:
    return last is not None and (now - last) <= stale_after


def build_footer(snap: dict, stale_after: float) -> str:
    now = time.monotonic()

    if _fresh(now, snap["last_ekf_nav_time"], stale_after):
        ins = _SOLUTION_MODE_LABELS.get(snap["solution_mode"], "?")
    else:
        ins = "--"

    if _fresh(now, snap["last_gps_pos_time"], stale_after):
        gps_type = _GPS_POS_TYPE_LABELS.get(snap["gps_pos_type"], "?")
        n = snap["num_sv_used"]
        sats = "--" if n is None or n == _NUM_SV_NA else str(n)
    else:
        gps_type = "--"
        sats = "--"

    return f"INS: {ins}  |  GPS: {gps_type}  |  sats: {sats}"


def render(snap: dict, stale_after: float) -> None:
    cols, rows = shutil.get_terminal_size((80, 24))

    # Determine state
    no_topic = not snap["has_publisher"]
    stale = (
        snap["last_gps_time"] is not None
        and (time.monotonic() - snap["last_gps_time"]) > stale_after
    )

    if no_topic:
        bg = BG_RED
        big = "NO GPS TOPIC"
        footer = "no publisher on topic — assuming NO FIX"
    elif stale or snap["gps_status"] is None:
        bg = BG_RED
        big = "NO FIX"
        footer = build_footer(snap, stale_after)
        if stale:
            footer = "(stale)  " + footer
    elif has_fix(snap["gps_status"]):
        bg = BG_GREEN
        big = "FIX"
        footer = build_footer(snap, stale_after)
    else:
        bg = BG_RED
        big = "NO FIX"
        footer = build_footer(snap, stale_after)

    block_rows = render_block_text(big)
    block_h = len(block_rows)
    block_w = max(len(r) for r in block_rows)

    style = bg + FG_WHITE + BOLD

    out = [HOME, style]

    # Paint every row with the bg color, full width.
    blank = " " * cols
    for _ in range(rows):
        out.append(blank)

    # Position the block text. Center vertically (excluding the footer line).
    top = max(0, (rows - 1 - block_h) // 2)
    left = max(0, (cols - block_w) // 2)
    for i, line in enumerate(block_rows):
        if top + i + 1 > rows - 1:
            break
        # Truncate if the terminal is too narrow.
        visible = line[: max(0, cols - left)]
        out.append(f"\033[{top + i + 1};{left + 1}H{visible}")

    # Footer on the last row, centered.
    footer = footer[:cols]
    fleft = max(0, (cols - len(footer)) // 2)
    out.append(f"\033[{rows};{fleft + 1}H{footer}")

    out.append(RESET)
    sys.stdout.write("".join(out))
    sys.stdout.flush()


def main() -> None:
    parser = argparse.ArgumentParser(description="Fullscreen GPS fix indicator")
    parser.add_argument(
        "--gps-topic",
        default="/ins/imu/nav_sat_fix",
        help="sensor_msgs/NavSatFix topic (default: /ins/imu/nav_sat_fix)",
    )
    parser.add_argument(
        "--ekf-nav-topic",
        default="/ins/sbg/ekf_nav",
        help="sbg_driver/SbgEkfNav topic for INS solution mode "
        "(default: /ins/sbg/ekf_nav)",
    )
    parser.add_argument(
        "--gps-pos-topic",
        default="/ins/sbg/gps_pos",
        help="sbg_driver/SbgGpsPos topic for GPS pos-type and sat count "
        "(default: /ins/sbg/gps_pos)",
    )
    parser.add_argument(
        "--rate",
        type=float,
        default=4.0,
        help="Redraw rate in Hz (default: 4)",
    )
    parser.add_argument(
        "--stale-after",
        type=float,
        default=3.0,
        help="Seconds without a NavSatFix message before treating as NO FIX (default: 3)",
    )
    args = parser.parse_args()

    rclpy.init()
    node = GpsFixNode(args.gps_topic, args.ekf_nav_topic, args.gps_pos_topic)

    spin_thread = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin_thread.start()

    sys.stdout.write(HIDE_CURSOR + CLEAR)
    sys.stdout.flush()

    # Repaint on terminal resize.
    redraw_event = threading.Event()

    def on_resize(_signum, _frame):
        # Force a full repaint on next tick.
        sys.stdout.write(CLEAR)
        sys.stdout.flush()
        redraw_event.set()

    signal.signal(signal.SIGWINCH, on_resize)

    interval = 1.0 / max(args.rate, 0.1)
    try:
        while rclpy.ok():
            snap = node.snapshot()
            render(snap, args.stale_after)
            redraw_event.wait(timeout=interval)
            redraw_event.clear()
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write(RESET + SHOW_CURSOR + CLEAR + HOME)
        sys.stdout.flush()
        rclpy.try_shutdown()


if __name__ == "__main__":
    main()
