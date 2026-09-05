import math
import random
import signal
import time
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")

from gi.repository import Gtk, GtkLayerShell, Gdk, GLib, Pango, PangoCairo  # noqa: E402
import cairo  # noqa: E402

CORNER_FONT = "Hack Nerd Font, Noto Sans CJK JP Bold 11"

RED = (1.0, 0.0, 0.314)
CYAN = (0.0, 1.0, 0.706)
AMBER = (1.0, 0.333, 0.0)
WHITE = (1.0, 1.0, 1.0)
BLACK = (0.0, 0.0, 0.0)

EDGE_PX = 32
PULSE_PERIOD = 0.85
MIN_ALPHA = 0.18
MAX_ALPHA = 0.92
FRAME_MS = 33
GLITCH_CHARS = "アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789ABCDEF!?/#@"

_start = time.monotonic()


class EdgeFlash(Gtk.Window):
    def __init__(self, monitor=None):
        super().__init__()

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "battery-critical-flash")
        if monitor is not None:
            GtkLayerShell.set_monitor(self, monitor)
        for edge in (
            GtkLayerShell.Edge.LEFT,
            GtkLayerShell.Edge.RIGHT,
            GtkLayerShell.Edge.TOP,
            GtkLayerShell.Edge.BOTTOM,
        ):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_interactivity(self, False)

        visual = self.get_screen().get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_accept_focus(False)

        self.connect("draw", self._on_draw)
        self.connect("realize", self._on_realize)
        self.connect("destroy", Gtk.main_quit)

        GLib.timeout_add(FRAME_MS, self._tick)

    def _apply_click_through(self):
        empty = cairo.Region()
        self.input_shape_combine_region(empty)
        gdk_win = self.get_window()
        if gdk_win is not None:
            gdk_win.input_shape_combine_region(empty, 0, 0)
        return False

    def _on_realize(self, *_):
        self._apply_click_through()
        GLib.idle_add(self._apply_click_through)

    def _tick(self):
        self.queue_draw()
        return True


    def _stroke_border(self, cr, w, h, rgb, alpha, dx=0, dy=0, width=EDGE_PX):
        r, g, b = rgb
        cr.save()
        cr.translate(dx, dy)
        cr.set_source_rgba(r, g, b, alpha)
        cr.set_line_width(width)
        inset = width / 2
        cr.rectangle(inset, inset, w - width, h - width)
        cr.stroke()
        cr.restore()

    def _scanlines(self, cr, w, h, t):
        cr.set_source_rgba(0, 0, 0, 0.42)
        cr.set_line_width(1)
        step = 3
        y_offset = int(t * 55) % step
        for y in range(y_offset, h, step):
            if y < EDGE_PX or y > h - EDGE_PX:
                cr.move_to(0, y + 0.5)
                cr.line_to(w, y + 0.5)
                cr.stroke()
            else:
                cr.move_to(0, y + 0.5)
                cr.line_to(EDGE_PX, y + 0.5)
                cr.stroke()
                cr.move_to(w - EDGE_PX, y + 0.5)
                cr.line_to(w, y + 0.5)
                cr.stroke()

    def _tears(self, cr, w, h):
        if random.random() > 0.55:
            return
        for _ in range(random.randint(1, 4)):
            thickness = random.randint(2, 10)
            shift = random.randint(-30, 30)
            color = random.choice((RED, CYAN, WHITE, AMBER))
            a = random.uniform(0.45, 1.0)
            cr.set_source_rgba(*color, a)
            band = random.choice(("top", "bot", "left", "right"))
            if band == "top":
                y = random.randint(0, EDGE_PX)
                cr.rectangle(shift, y, w, thickness)
            elif band == "bot":
                y = random.randint(h - EDGE_PX, h - thickness)
                cr.rectangle(shift, y, w, thickness)
            elif band == "left":
                x = random.randint(0, EDGE_PX)
                y = random.randint(0, h - thickness)
                cr.rectangle(x, y + shift, thickness, random.randint(8, 40))
            else:
                x = random.randint(w - EDGE_PX, w - thickness)
                y = random.randint(0, h - thickness)
                cr.rectangle(x, y + shift, thickness, random.randint(8, 40))
            cr.fill()

    def _draw_pango(self, cr, x, y, text, rgb, alpha):
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription(CORNER_FONT))
        layout.set_text(text, -1)
        cr.set_source_rgba(*rgb, alpha)
        cr.move_to(x, y)
        PangoCairo.show_layout(cr, layout)

    def _corner_garbage(self, cr, w, h, t):
        rng = random.Random(int(t * 5))

        def gib(n):
            return "".join(rng.choice(GLITCH_CHARS) for _ in range(n))

        corners = [
            (8, 4, gib(7), CYAN),
            (w - 120, 4, gib(7), RED),
            (8, h - 22, "LOW//: " + gib(3), AMBER),
            (w - 120, h - 22, gib(7), CYAN),
        ]
        for x, y, text, rgb in corners:
            self._draw_pango(cr, x + 1, y + 1, text, BLACK, 0.85)
            self._draw_pango(cr, x, y, text, rgb, 0.9)


    def _on_draw(self, _widget, cr):
        w = self.get_allocated_width()
        h = self.get_allocated_height()

        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        t = time.monotonic() - _start

        base = 0.5 - 0.5 * math.cos(2 * math.pi * t / PULSE_PERIOD)
        roll = random.random()
        if roll < 0.05:
            base = 0.05
        elif roll < 0.09:
            base = 1.0
        elif roll < 0.14:
            base = random.uniform(0, 1)
        alpha = MIN_ALPHA + (MAX_ALPHA - MIN_ALPHA) * base

        split = 3 + int(5 * math.sin(t * 7.3) + 3 * math.sin(t * 13.1))
        self._stroke_border(cr, w, h, RED, alpha, dx=0, dy=0)
        self._stroke_border(cr, w, h, CYAN, alpha * 0.55, dx=-split, dy=0)
        self._stroke_border(cr, w, h, WHITE, alpha * 0.22, dx=split, dy=2)

        inner_alpha = alpha * 0.35 * (1.0 if random.random() > 0.18 else 0.0)
        self._stroke_border(
            cr, w, h, AMBER, inner_alpha, dx=0, dy=0, width=max(2, EDGE_PX // 6)
        )

        self._scanlines(cr, w, h, t)
        self._tears(cr, w, h)
        self._corner_garbage(cr, w, h, t)

        return False


def _install_signal_handlers():
    def _quit(*_):
        Gtk.main_quit()
        return False

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, _quit)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, _quit)


def main():
    _install_signal_handlers()
    display = Gdk.Display.get_default()
    wins = []
    for i in range(display.get_n_monitors()):
        w = EdgeFlash(monitor=display.get_monitor(i))
        w.show_all()
        wins.append(w)
    Gtk.main()


if __name__ == "__main__":
    main()
