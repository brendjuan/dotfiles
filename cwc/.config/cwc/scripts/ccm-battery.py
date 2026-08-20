#!/usr/bin/env python3
"""
ccm-battery.py — CCM pack voltage + current for waybar, straight off ros2.

subscribes to /ccm/battery (sensor_msgs/BatteryState) and prints one waybar json
line per redraw. this is a *continuous* module (no "interval" in config.jsonc):
waybar keeps us alive and reads stdout, so we choose our own refresh rate.

two speeds:
  LIVE — samples arriving: redraw once a second, never faster.
  DOWN — no publisher, or nothing heard for STALE_AFTER seconds: redraw every 30s.

the subscription itself is push-based, so a sample landing while we are DOWN wakes
the wait right away and we go LIVE immediately. the 30s only caps how often we
redraw the dead chip.

waybar is spawned by the compositor, so its environment has no ros in it. we
re-exec ourselves through bash with /opt/ros/jazzy/setup.bash sourced, plus the
dotfiles env.sh that carries CYCLONEDDS_URI (the pack talks to us over loopback,
so that xml is not optional).
"""
import importlib.util
import json
import math
import os
import signal
import sys
import time

TOPIC = "/ccm/battery"
NODE_NAME = "waybar_ccm_battery"

LIVE_INTERVAL = 1.0    # hardest we redraw once comms are up
DOWN_INTERVAL = 30.0   # light poll while the topic is dead
STALE_AFTER = 5.0      # no sample for this long = comms are down

ICON = "󱐋"  # nf-md-lightning_bolt — pack telemetry, not the laptop battery

ROS_SETUP = "/opt/ros/jazzy/setup.bash"
DOTFILES_ENV = "~/.config/dotfiles/env.sh"
GUARD = "CCM_BATTERY_ROS_ENV"  # set before re-exec so we only do it once

# sensor_msgs/BatteryState constants, spelled out for the tooltip
STATUS = {0: "unknown", 1: "charging", 2: "discharging", 3: "not charging", 4: "full"}
HEALTH = {
    0: "unknown", 1: "good", 2: "overheat", 3: "dead", 4: "overvoltage",
    5: "unspecified failure", 6: "cold", 7: "watchdog timeout", 8: "safety timeout",
}


def bootstrap():
    """re-exec inside a shell that has ros sourced. no-op if it already is."""
    if os.environ.get(GUARD) or importlib.util.find_spec("rclpy") is not None:
        return
    if not os.path.exists(ROS_SETUP):
        return  # nothing to source — main() reports the missing rclpy instead
    os.environ[GUARD] = "1"
    os.environ.setdefault("RMW_IMPLEMENTATION", "rmw_cyclonedds_cpp")
    env_sh = os.path.expanduser(DOTFILES_ENV)
    cmd = (f'[ -f "{env_sh}" ] && . "{env_sh}"; . "{ROS_SETUP}"; '
           f'exec "{sys.executable}" "{os.path.realpath(__file__)}" "$@"')
    os.execvp("bash", ["bash", "-c", cmd, "bash", *sys.argv[1:]])


def finite(x):
    """BatteryState fields are allowed to be NaN. treat those as absent."""
    try:
        return x is not None and math.isfinite(x)
    except TypeError:
        return False


def unit(value, suffix, digits=1):
    return f"?{suffix}" if not finite(value) else f"{value:.{digits}f}{suffix}"


def pack_percent(msg):
    """ros spec says percentage is 0..1. some firmware sends 0..100 — take both."""
    p = msg.percentage
    if not finite(p):
        return None
    return p * 100.0 if p <= 1.0 else p


def color_class(pct):
    # unknown charge = no opinion, stay teal
    if pct is None:
        return "green"
    if pct < 15:
        return "red"
    if pct < 30:
        return "orange"
    if pct < 50:
        return "yellow"
    return "green"


def emit(text, tooltip, cls, percentage=None):
    payload = {"text": text, "tooltip": tooltip, "class": cls, "alt": cls}
    if percentage is not None:
        payload["percentage"] = int(percentage)
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def draw_live(msg, age):
    volts = msg.voltage if finite(msg.voltage) else None
    amps = msg.current if finite(msg.current) else None
    pct = pack_percent(msg)

    lines = [f"CCM BATTERY :: {unit(volts, 'V')} · {unit(amps, 'A')}"]
    if volts is not None and amps is not None:
        lines.append(f"  power:   {abs(volts * amps):.0f} W")
    status = STATUS.get(msg.power_supply_status, "?")
    if pct is not None:
        lines.append(f"  pack:    {pct:.0f}% ({status})")
    else:
        lines.append(f"  pack:    {status}")
    if finite(msg.temperature):
        lines.append(f"  temp:    {msg.temperature:.1f} °C")
    if finite(msg.charge):
        cap = f" / {msg.capacity:.1f}" if finite(msg.capacity) else ""
        lines.append(f"  charge:  {msg.charge:.1f}{cap} Ah")
    cells = [c for c in (msg.cell_voltage or []) if finite(c)]
    if cells:
        lines.append(f"  cells:   {len(cells)} · {min(cells):.2f}–{max(cells):.2f}V")
    health = HEALTH.get(msg.power_supply_health)
    if health and health != "good":
        lines.append(f"  health:  {health}")
    if not msg.present:
        lines.append("  present: false")
    lines.append(f"  topic:   {TOPIC} ({age:.1f}s ago)")

    emit(f"{ICON} {unit(volts, 'V')} {unit(amps, 'A')}",
         "\n".join(lines), color_class(pct), pct)


def draw_starting():
    """first line out, printed before the rclpy import.

    waybar hides a custom module until it prints something, and importing rclpy
    plus building a dds participant costs about a second. without this the chip
    is missing for that second after every waybar reload — e.g. a high-contrast
    swap — and the chip cluster next to it visibly jumps sideways.
    """
    emit(f"{ICON} --",
         f"CCM BATTERY :: starting\n  topic:   {TOPIC}\n  state:   connecting to ros",
         "down")


def draw_down(publishers, msg, age):
    lines = [f"CCM BATTERY :: no data", f"  topic:   {TOPIC}"]
    if publishers:
        lines.append(f"  state:   {publishers} publisher(s) up, silent")
    else:
        lines.append("  state:   nobody publishing")
    if msg is not None:
        lines.append(f"  last:    {unit(msg.voltage, 'V')} · {unit(msg.current, 'A')}"
                     f" ({age:.0f}s ago)")
    lines.append(f"  poll:    every {DOWN_INTERVAL:.0f}s until it comes back")
    emit(f"{ICON} --", "\n".join(lines), "down")


def run():
    import rclpy
    from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
    from sensor_msgs.msg import BatteryState

    # best-effort talks to reliable *and* best-effort publishers, so we never get
    # dropped on a qos mismatch. depth 1 because only the newest sample matters.
    qos = QoSProfile(
        depth=1,
        history=HistoryPolicy.KEEP_LAST,
        reliability=ReliabilityPolicy.BEST_EFFORT,
        durability=DurabilityPolicy.VOLATILE,
    )

    rclpy.init(args=[])
    node = rclpy.create_node(f"{NODE_NAME}_{os.getpid()}")
    last = {"msg": None, "at": 0.0}

    def on_msg(msg):
        last["msg"] = msg
        last["at"] = time.monotonic()

    node.create_subscription(BatteryState, TOPIC, on_msg, qos)

    last_emit = 0.0
    was_live = None
    try:
        while rclpy.ok():
            now = time.monotonic()
            age = now - last["at"]
            live = last["msg"] is not None and age < STALE_AFTER
            period = LIVE_INTERVAL if live else DOWN_INTERVAL
            # state flips redraw at once; otherwise we honour the period
            if live != was_live or (now - last_emit) >= period:
                if live:
                    draw_live(last["msg"], age)
                else:
                    draw_down(node.count_publishers(TOPIC), last["msg"], age)
                last_emit, was_live = time.monotonic(), live
            # one blocking wait in the dds waitset — 1s when live, 30s when down.
            # an incoming sample returns early, so recovery is not delayed.
            rclpy.spin_once(node, timeout_sec=max(0.05, last_emit + period - time.monotonic()))
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    bootstrap()
    if "--echo" in sys.argv[1:]:
        # what the on-click opens: raw samples in a float terminal
        os.execvp("ros2", ["ros2", "topic", "echo", TOPIC])
    draw_starting()
    try:
        run()
    except (KeyboardInterrupt, BrokenPipeError, SystemExit):
        return
    except ImportError as e:
        # no rclpy at all. print the dead chip and exit — waybar's restart-interval
        # brings us back in 30s, which is the light poll for "ros isn't here yet".
        emit(f"{ICON} --", f"CCM BATTERY :: no rclpy\n  {e}\n  retry:   {DOWN_INTERVAL:.0f}s", "down")
    except Exception as e:
        emit(f"{ICON} --",
             f"CCM BATTERY :: {e.__class__.__name__}\n  {e}\n  retry:   {DOWN_INTERVAL:.0f}s",
             "down")


if __name__ == "__main__":
    main()
