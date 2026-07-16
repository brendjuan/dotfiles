#!/usr/bin/env python3
"""
device-notify.py — pop a mako notification when a device is hotplugged.

Wraps `udevadm monitor` (systemd/udev, no pip deps — same house rule as
package-tracker.py) and turns each add/remove into a notify-send popup, the
same way the high-contrast toggle fires one. No root, no polling: udev streams
kernel uevents the instant the kernel emits them, and only from when we start —
so there's no coldplug flood at login (internal usb is enumerated at boot,
long before oneshot.lua spawns us).

What counts as "a device" — we announce it at the layer that carries the /dev
node you actually want, not the raw /dev/bus/usb/BBB/DDD one:

  • Serial: SUBSYSTEM=tty, DEVNAME=/dev/ttyUSB* or /dev/ttyACM* — usb-serial
            bridges (FTDI / CP210x / CH340) and CDC-ACM boards (Pico, Arduino,
            most microcontrollers). The name gate also dodges the built-in
            /dev/ttyS0 and the /dev/tty0-63 virtual consoles.

  • Disks:  SUBSYSTEM=block, DEVTYPE=disk with a physical ID_PATH — usb sticks
            (/dev/sdX), SD cards in a reader (/dev/mmcblkX), internal SATA/NVMe
            hotplug. loop / ram / zram / dm / md have NO ID_PATH, so snap &
            AppImage loop churn stays silent, and partitions (DEVTYPE=partition)
            are ignored so one disk is one popup.

We deliberately DON'T listen to the raw usb_device layer: its only node is the
/dev/bus/usb/003/005 bus path. The tty/block events already carry the same
vendor+model (ID_VENDOR/ID_MODEL) *and* the human-readable node. Trade-off:
pure-HID / webcam / audio USB gear (no tty or block node) goes unannounced —
add its subsystem to SUBSYSTEMS below if you want it back.

Spawned once at login from oneshot.lua. Exits cleanly on SIGTERM/SIGINT so a
relaunch — or `pkill -f device-notify.py` — never strands the udevadm child.

Tweak knobs live up top: NOTIFY_ON_REMOVE (False = connect-only), URGENCY, ICON.
"""
import signal
import subprocess
import sys
import time

# ── knobs ───────────────────────────────────────────────────────────────
NOTIFY_ON_REMOVE = True      # False → only announce connects, ignore removals
URGENCY = "low"              # matches the high-contrast toggle's -u low
APP_NAME = "device-notify"   # groups these in mako (cf. battery.lua's -a battery-monitor)
ICON = "drive-removable-media"

# udev subsystems we bother listening to. Narrowing at the source keeps the
# firehose down — no input-event / hidraw / sound spam ever reaches the parser.
SUBSYSTEMS = ("tty", "block")


def interesting(p):
    """True if this uevent is a device a human plugged in, seen at the layer
    that carries the useful /dev node (a ttyACM/ttyUSB port, or a whole disk)."""
    sub, dtype = p.get("SUBSYSTEM"), p.get("DEVTYPE")
    if sub == "tty":
        # ttyUSB* = usb-serial bridges, ttyACM* = CDC-ACM boards. The name gate
        # is also what filters out /dev/ttyS0 and the /dev/tty0-63 consoles.
        return p.get("DEVNAME", "").startswith(("/dev/ttyUSB", "/dev/ttyACM"))
    if sub == "block" and dtype == "disk":
        # a real physical disk has an ID_PATH; loop / ram / zram / dm / md don't.
        # usb sticks included — we WANT their /dev/sdX node, not the bus path.
        return bool(p.get("ID_PATH"))
    return False


def describe(p):
    """Best human name for the device, richest field first, hex as last resort."""
    vendor = (p.get("ID_VENDOR") or p.get("ID_VENDOR_FROM_DATABASE") or "").strip()
    model = (p.get("ID_MODEL") or p.get("ID_MODEL_FROM_DATABASE") or "").strip()
    # udev encodes spaces as underscores in the descriptor-derived fields
    name = f"{vendor} {model}".replace("_", " ").strip()
    if not name:                           # no friendly strings — try vendor:product ids
        vid, pid = p.get("ID_VENDOR_ID"), p.get("ID_MODEL_ID")
        name = f"{vid}:{pid}" if vid and pid else p.get("SUBSYSTEM", "device")
    node = p.get("DEVNAME", "")
    detail = node if node.startswith("/dev/") else ""
    return name, detail


def notify(action, p):
    name, detail = describe(p)
    summary = "Device connected" if action == "add" else "Device disconnected"
    body = f"{name}\n{detail}" if detail else name
    subprocess.run(
        ["notify-send", "-u", URGENCY, "-a", APP_NAME, "-i", ICON, summary, body],
        check=False,
    )


def events():
    """Yield (action, props) per udev uevent; respawn udevadm if it ever exits."""
    cmd = ["stdbuf", "-oL", "udevadm", "monitor", "--udev", "--property"]
    cmd += [f"--subsystem-match={s}" for s in SUBSYSTEMS]
    while True:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
        props = {}
        try:
            for line in proc.stdout:
                line = line.rstrip("\n")
                if not line:                   # blank line ends one event block
                    action = props.get("ACTION")
                    if action:
                        yield action, props
                    props = {}
                elif "=" in line:              # KEY=VALUE property
                    k, _, v = line.partition("=")
                    props[k] = v
                # else: the "UDEV [t] add /devices/... (usb)" header — skip
        finally:
            proc.terminate()
        time.sleep(1)                          # udevadm died; back off and respawn


def main():
    # clean exit so an oneshot relaunch / pkill doesn't leave udevadm orphaned
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    for action, props in events():
        if not interesting(props):
            continue
        if action == "add":
            notify("add", props)
        elif action == "remove" and NOTIFY_ON_REMOVE:
            notify("remove", props)


if __name__ == "__main__":
    main()
