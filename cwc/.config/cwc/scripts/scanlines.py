import argparse
import math
import random
import signal
import time
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import Gtk, GtkLayerShell, Gdk, GLib  # noqa: E402
import cairo  # noqa: E402

FRAME_MS = 33


class Scanlines(Gtk.Window):
    def __init__(self, alpha, step, scroll, hum_bar, glitch_roll, monitor=None):
        super().__init__()
        self.alpha = alpha
        self.step = max(1, step)
        self.scroll = scroll
        self.hum_bar = hum_bar
        self.glitch_roll = glitch_roll
        self._start = time.monotonic()
        self._roll = None

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "scanlines")
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

        if self.scroll != 0.0 or self.hum_bar or self.glitch_roll:
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

    def _on_draw(self, _widget, cr):
        w = self.get_allocated_width()
        h = self.get_allocated_height()

        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        t = time.monotonic() - self._start

        y_off = (t * self.scroll) % self.step if self.scroll else 0.0

        jump_px = 0
        if self.glitch_roll:
            if self._roll is None and random.random() < 0.012:
                duration = random.uniform(0.08, 0.22)
                jump = random.choice((-1, 1)) * random.randint(12, 60)
                self._roll = (t + duration, jump, random.randint(0, h))
            if self._roll is not None:
                end_t, jump_px, tear_y = self._roll
                if t > end_t:
                    self._roll = None
                    jump_px = 0
                else:
                    cr.set_source_rgba(0, 0, 0, min(0.85, self.alpha * 2.0))
                    cr.rectangle(0, tear_y - 2, w, 4)
                    cr.fill()

        cr.set_source_rgba(0, 0, 0, self.alpha)
        cr.set_line_width(1)
        y = -self.step + y_off + jump_px
        while y < h + abs(jump_px):
            if -1 <= y < h:
                cr.move_to(0, y + 0.5)
                cr.line_to(w, y + 0.5)
                cr.stroke()
            y += self.step

        if self.hum_bar:
            bar_speed = 90
            bar_height = 80 + int(20 * math.sin(t * 0.9))
            bar_y = (t * bar_speed) % (h + bar_height) - bar_height

            grad = cairo.LinearGradient(0, bar_y, 0, bar_y + bar_height)
            peak = min(0.75, self.alpha * 2.0)
            grad.add_color_stop_rgba(0.0, 0, 0, 0, 0)
            grad.add_color_stop_rgba(0.5, 0, 0, 0, peak)
            grad.add_color_stop_rgba(1.0, 0, 0, 0, 0)
            cr.set_source(grad)
            cr.rectangle(0, bar_y, w, bar_height)
            cr.fill()

            bar2_y = ((t + 4.2) * bar_speed * 0.7) % (h + 40) - 40
            grad2 = cairo.LinearGradient(0, bar2_y, 0, bar2_y + 40)
            peak2 = min(0.55, self.alpha * 1.4)
            grad2.add_color_stop_rgba(0.0, 0, 0, 0, 0)
            grad2.add_color_stop_rgba(0.5, 0, 0, 0, peak2)
            grad2.add_color_stop_rgba(1.0, 0, 0, 0, 0)
            cr.set_source(grad2)
            cr.rectangle(0, bar2_y, w, 40)
            cr.fill()

        return False


def _parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--alpha", type=float, default=0.14)
    p.add_argument("--step", type=int, default=3)
    p.add_argument("--scroll", type=float, default=0.0,
                   help="vertical scroll speed in px/sec (0 = static)")
    p.add_argument("--hum-bar", action="store_true",
                   help="add a slow VCR tracking bar rolling down the screen")
    p.add_argument("--glitch-roll", action="store_true",
                   help="inject random VCR tracking-failure jumps")
    return p.parse_args()


def main():
    args = _parse_args()

    def _quit(*_):
        Gtk.main_quit()
        return False

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, _quit)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, _quit)

    display = Gdk.Display.get_default()
    n = display.get_n_monitors()
    wins = []
    for i in range(n):
        w = Scanlines(
            alpha=args.alpha,
            step=args.step,
            scroll=args.scroll,
            hum_bar=args.hum_bar,
            glitch_roll=args.glitch_roll,
            monitor=display.get_monitor(i),
        )
        w.show_all()
        wins.append(w)

    Gtk.main()


if __name__ == "__main__":
    main()
