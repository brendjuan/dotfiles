import signal
import subprocess
import sys
import time

NOTIFY_ON_REMOVE = True
URGENCY = "low"
APP_NAME = "device-notify"
ICON = "drive-removable-media"

SUBSYSTEMS = ("tty", "block")


def interesting(p):
    sub, dtype = p.get("SUBSYSTEM"), p.get("DEVTYPE")
    if sub == "tty":
        return p.get("DEVNAME", "").startswith(("/dev/ttyUSB", "/dev/ttyACM"))
    if sub == "block" and dtype == "disk":
        return bool(p.get("ID_PATH"))
    return False


def describe(p):
    vendor = (p.get("ID_VENDOR") or p.get("ID_VENDOR_FROM_DATABASE") or "").strip()
    model = (p.get("ID_MODEL") or p.get("ID_MODEL_FROM_DATABASE") or "").strip()
    name = f"{vendor} {model}".replace("_", " ").strip()
    if not name:
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
    cmd = ["stdbuf", "-oL", "udevadm", "monitor", "--udev", "--property"]
    cmd += [f"--subsystem-match={s}" for s in SUBSYSTEMS]
    while True:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
        props = {}
        try:
            for line in proc.stdout:
                line = line.rstrip("\n")
                if not line:
                    action = props.get("ACTION")
                    if action:
                        yield action, props
                    props = {}
                elif "=" in line:
                    k, _, v = line.partition("=")
                    props[k] = v
        finally:
            proc.terminate()
        time.sleep(1)


def main():
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
