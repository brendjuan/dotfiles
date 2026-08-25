#!/usr/bin/env python3
"""
ccm-battery.py — CCM pack voltage + current for waybar, over the Foxglove bridge.

connects to the vehicle's foxglove_bridge websocket (the same endpoint the
Foxglove app uses) and subscribes to /ccm/battery (sensor_msgs/BatteryState).
prints one waybar json line per redraw. this is a *continuous* module (no
"interval" in config.jsonc): waybar keeps us alive and reads stdout, so we
choose our own refresh rate.

SUBSCRIBE-ONLY, BY DESIGN. this used to be an rclpy node, but any dds
participant on the operator laptop pollutes the vehicle's graph (discovery,
rosout, parameter services), and feeding the topic through a local
zenoh-bridge-ros2dds made that bridge advertise a phantom pub route that
blocked the real battery data from entering zenoh. the foxglove websocket
protocol has no such feedback path: the bridge node on the VEHICLE does the
dds work, and this client only ever sends the handshake and one "subscribe"
request. it advertises nothing, publishes nothing, and touches neither dds
nor zenoh.

two speeds:
  LIVE — samples arriving: redraw once a second, never faster.
  DOWN — bridge unreachable, topic not advertised, or silent for STALE_AFTER
         seconds: redraw / reconnect every 30s.

BatteryState is decoded from cdr by hand (see CdrReader) so the chip needs no
ros install at all — just python3 + the "websockets" package.
"""
import asyncio
import json
import math
import signal
import struct
import sys
import time

URL = "ws://ccm-cm5-0:8765"
# the bridge picks one of these. foxglove-bridge 3.x (built on
# foxglove-sdk-cpp) answers only to "foxglove.sdk.v1"; the older
# websocketpp bridge answered only to "foxglove.websocket.v1". a bridge
# that wants a name we did not offer rejects the handshake with HTTP 400,
# so we offer both and let it choose. the wire protocol is the same.
SUBPROTOCOLS = ["foxglove.sdk.v1", "foxglove.websocket.v1"]
TOPIC = "/ccm/battery"

LIVE_INTERVAL = 1.0    # hardest we redraw once comms are up
DOWN_INTERVAL = 30.0   # reconnect / redraw cadence while the topic is dead
STALE_AFTER = 5.0      # no sample for this long = comms are down

ICON = "󱐋"  # nf-md-lightning_bolt — pack telemetry, not the laptop battery

# sensor_msgs/BatteryState constants, spelled out for the tooltip
STATUS = {0: "unknown", 1: "charging", 2: "discharging", 3: "not charging", 4: "full"}
HEALTH = {
    0: "unknown", 1: "good", 2: "overheat", 3: "dead", 4: "overvoltage",
    5: "unspecified failure", 6: "cold", 7: "watchdog timeout", 8: "safety timeout",
}

ECHO = "--echo" in sys.argv[1:]


# ── cdr decoding ──────────────────────────────────────────────────────
class CdrReader:
    """minimal xcdr1 reader — just what BatteryState needs.

    layout: 4-byte encapsulation header (kind uint16 big-endian: 0x0000 CDR_BE,
    0x0001 CDR_LE; 2 option bytes), then the fields. alignment is relative to
    the first byte AFTER the header.
    """

    def __init__(self, buf):
        if len(buf) < 4:
            raise ValueError("cdr payload shorter than its encapsulation header")
        self.end = "<" if buf[1] & 1 else ">"
        self.buf = buf
        self.pos = 4

    def _align(self, n):
        off = (self.pos - 4) % n
        if off:
            self.pos += n - off

    def _take(self, fmt, size, align):
        self._align(align)
        val = struct.unpack_from(self.end + fmt, self.buf, self.pos)[0]
        self.pos += size
        return val

    def u8(self):
        return self._take("B", 1, 1)

    def i32(self):
        return self._take("i", 4, 4)

    def u32(self):
        return self._take("I", 4, 4)

    def f32(self):
        return self._take("f", 4, 4)

    def string(self):
        n = self.u32()  # length including the terminating null
        raw = self.buf[self.pos:self.pos + n]
        self.pos += n
        return raw.rstrip(b"\x00").decode("utf-8", "replace")

    def f32_seq(self):
        n = self.u32()
        self._align(4)
        vals = list(struct.unpack_from(f"{self.end}{n}f", self.buf, self.pos))
        self.pos += 4 * n
        return vals


class BatteryState:
    """field-for-field mirror of sensor_msgs/msg/BatteryState (jazzy)."""

    def __init__(self, payload):
        c = CdrReader(payload)
        self.stamp_sec = c.i32()
        self.stamp_nanosec = c.u32()
        self.frame_id = c.string()
        self.voltage = c.f32()
        self.temperature = c.f32()
        self.current = c.f32()
        self.charge = c.f32()
        self.capacity = c.f32()
        self.design_capacity = c.f32()
        self.percentage = c.f32()
        self.power_supply_status = c.u8()
        self.power_supply_health = c.u8()
        self.power_supply_technology = c.u8()
        self.present = c.u8() != 0
        self.cell_voltage = c.f32_seq()
        self.cell_temperature = c.f32_seq()
        self.location = c.string()
        self.serial_number = c.string()


# ── formatting (unchanged waybar contract: same classes, same layout) ─
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
    lines.append(f"  source:  {URL} → {TOPIC} ({age:.1f}s ago)")

    emit(f"{ICON} {unit(volts, 'V')} {unit(amps, 'A')}",
         "\n".join(lines), color_class(pct), pct)


def draw_down(reason, msg=None, age=None):
    lines = [f"CCM BATTERY :: no data", f"  source:  {URL} → {TOPIC}", f"  state:   {reason}"]
    if msg is not None:
        lines.append(f"  last:    {unit(msg.voltage, 'V')} · {unit(msg.current, 'A')}"
                     f" ({age:.0f}s ago)")
    lines.append(f"  poll:    every {DOWN_INTERVAL:.0f}s until it comes back")
    emit(f"{ICON} --", "\n".join(lines), "down")


def why(e):
    """short, readable reason for the tooltip.

    the exception class name alone hides the case that matters: a rejected
    handshake (HTTP 400) means the bridge wanted a subprotocol we did not
    offer, and that reads exactly like "the host is down".
    """
    status = getattr(e, "status_code", None)          # websockets < 12
    if status is None:                                # websockets >= 12
        status = getattr(getattr(e, "response", None), "status_code", None)
    if status is not None:
        return f"bridge refused the handshake (HTTP {status})"
    if isinstance(e, asyncio.TimeoutError):
        return "bridge did not answer in time"
    text = str(e).strip()
    return f"{e.__class__.__name__}: {text}" if text else e.__class__.__name__


def echo_sample(msg):
    """--echo mode: one decoded sample per line, for the float terminal."""
    print(json.dumps({k: v for k, v in vars(msg).items()}, default=str), flush=True)


# ── the client ────────────────────────────────────────────────────────
class State:
    def __init__(self):
        self.msg = None      # last sample that carried a real reading
        self.at = 0.0        # when that sample arrived
        self.seen_at = 0.0   # when ANY sample arrived, blank frames included
        self.blank = False   # was the most recent sample a blank frame?
        self.last_emit = 0.0
        self.was_live = None

    def forget(self):
        """drop the cached reading — the connection went away under us."""
        self.msg = None
        self.blank = False
        self.was_live = None

    def live(self):
        return self.msg is not None and (time.monotonic() - self.at) < STALE_AFTER

    def observe(self, msg):
        """record one decoded sample.

        the broadcaster sometimes publishes a blank frame: every float NaN,
        present false, status "not charging". that means "no reading right
        now", not "the pack is at 0V". they arrive in ones and twos between
        good samples, so keep showing the last real reading and let the normal
        STALE_AFTER timeout decide when to give up on it.
        """
        self.seen_at = time.monotonic()
        self.blank = not (finite(msg.voltage) or finite(msg.current))
        if not self.blank:
            self.msg, self.at = msg, self.seen_at

    def redraw(self, reason_when_down):
        now = time.monotonic()
        age = now - self.at
        live = self.live()
        period = LIVE_INTERVAL if live else DOWN_INTERVAL
        if live != self.was_live or (now - self.last_emit) >= period:
            if live:
                draw_live(self.msg, age)
            else:
                draw_down(reason_when_down, self.msg, age if self.msg else None)
            self.last_emit, self.was_live = time.monotonic(), live
        return live


def down_reason(state, channel_id):
    if channel_id is None:
        return "connected, topic not advertised"
    if state.blank and (time.monotonic() - state.seen_at) < STALE_AFTER:
        return "publisher reports no battery data"
    return "subscribed, publisher silent"


async def session(ws, state):
    """one connected websocket: find the channel, subscribe, pump samples."""
    import websockets
    channel_id = None
    sub_id = 1
    while True:
        live = state.live()
        timeout = LIVE_INTERVAL if live else min(DOWN_INTERVAL, 5.0)
        try:
            raw = await asyncio.wait_for(ws.recv(), timeout)
        except asyncio.TimeoutError:
            raw = None
        except websockets.ConnectionClosed:
            return

        if isinstance(raw, (bytes, bytearray)):
            # 0x01 = MessageData: u8 opcode, u32 subscription id, u64 receive ts, payload
            if raw[0] == 0x01 and len(raw) > 13:
                try:
                    msg = BatteryState(bytes(raw[13:]))
                except Exception as e:
                    draw_down(f"cdr decode failed: {e}")
                    continue
                state.observe(msg)
                if ECHO:
                    echo_sample(msg)
        elif raw is not None:
            data = json.loads(raw)
            op = data.get("op")
            if op == "advertise":
                for ch in data.get("channels", []):
                    if ch.get("topic") == TOPIC and channel_id is None:
                        channel_id = ch["id"]
                        # the ONLY request we ever make of the graph
                        await ws.send(json.dumps({
                            "op": "subscribe",
                            "subscriptions": [{"id": sub_id, "channelId": channel_id}],
                        }))
            elif op == "unadvertise":
                if channel_id in data.get("channelIds", []):
                    channel_id = None

        if not ECHO:
            state.redraw(down_reason(state, channel_id))


async def main_loop():
    try:
        import websockets
    except ImportError as e:
        emit(f"{ICON} --", f"CCM BATTERY :: no websockets package\n  {e}", "down")
        return
    state = State()
    while True:
        try:
            async with websockets.connect(
                URL, subprotocols=SUBPROTOCOLS, max_size=None, open_timeout=10,
            ) as ws:
                await session(ws, state)
        except Exception as e:
            reason = why(e)
            if ECHO:
                print(f"[{reason}] retry in {DOWN_INTERVAL:.0f}s",
                      file=sys.stderr, flush=True)
            else:
                state.forget()
                state.redraw(reason)
        await asyncio.sleep(DOWN_INTERVAL if state.msg is None else 1.0)


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if not ECHO:
        # first line out, before the connect: waybar hides a custom module until
        # it prints something, and without this the chip cluster jumps sideways
        # after every waybar reload (e.g. a high-contrast swap).
        emit(f"{ICON} --",
             f"CCM BATTERY :: starting\n  source:  {URL} → {TOPIC}\n  state:   connecting",
             "down")
    try:
        asyncio.run(main_loop())
    except (KeyboardInterrupt, BrokenPipeError, SystemExit):
        pass


if __name__ == "__main__":
    main()
