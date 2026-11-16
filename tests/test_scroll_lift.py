"""Scroll lift, tracking-id flicker and resting-finger checks for the daemon's Engine.

The Magic Mouse sends a touch report every ~11 ms while a finger is down and
nothing at all once it lifts, and hid-magicmouse can re-report a finger under a
new tracking id. These tests feed synthetic touch reports shaped like a real
recording (Magic Mouse USB-C, 004c:0323) into the Engine.

Run from the repo root:  python3 -m unittest discover -s tests -v
"""
import importlib.machinery
import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DAEMON = os.path.join(ROOT, "bin", "magic-mouse-daemon")

try:
    loader = importlib.machinery.SourceFileLoader("magic_mouse_daemon", DAEMON)
    spec = importlib.util.spec_from_loader("magic_mouse_daemon", loader)
    mmd = importlib.util.module_from_spec(spec)
    loader.exec_module(mmd)
except ImportError as exc:  # python-evdev missing
    mmd = None
    SKIP = f"daemon not importable: {exc}"
else:
    SKIP = ""

DT = 0.011  # report interval


class Ev:
    __slots__ = ("ts", "type", "code", "value")

    def __init__(self, ts, t, c, v):
        self.ts, self.type, self.code, self.value = ts, t, c, v

    def timestamp(self):
        return self.ts


class FakeUI:
    def __init__(self):
        self.events = []

    def write(self, t, c, v):
        self.events.append((t, c, v))

    def syn(self):
        pass


@unittest.skipIf(mmd is None, SKIP)
class ScrollLiftCase(unittest.TestCase):
    def setUp(self):
        cfg = mmd.load_config(os.path.join(ROOT, "does-not-exist.toml"))
        self.ui = FakeUI()
        self.eng = mmd.Engine(cfg, self.ui, verbose=False)
        self.t = 1000.0

    def report(self, contacts):
        """One HID touch report: contacts is a list of (slot, tracking_id, x, y)."""
        e = mmd.e
        for slot, tid, x, y in contacts:
            for code, value in ((e.ABS_MT_SLOT, slot), (e.ABS_MT_TRACKING_ID, tid),
                                (e.ABS_MT_POSITION_X, x), (e.ABS_MT_POSITION_Y, y)):
                self.eng.feed(Ev(self.t, e.EV_ABS, code, value))
        self.eng.feed(Ev(self.t, e.EV_SYN, e.SYN_REPORT, 0))
        self.t += DT

    def stroke(self, frames, x=-600, y0=500, dy=-40, slot=0, tid=1, extra=()):
        """A finger sliding forward at ~1 mm per report; returns the next y."""
        y = y0
        for _ in range(frames):
            self.report([(slot, tid, x, y), *extra])
            y += dy
        return y

    def lift(self):
        """The finger lifts: the mouse just stops reporting; the main loop notices."""
        self.eng.idle(self.t - DT + mmd.LIFT_SILENCE + 0.001)

    def wheel(self):
        e = mmd.e
        return sum(v for t, c, v in self.ui.events if t == e.EV_REL and c == e.REL_WHEEL_HI_RES)

    def test_silence_after_a_flick_starts_momentum(self):
        self.stroke(25)
        self.assertTrue(self.eng.scrolling)
        self.assertFalse(self.eng.coasting)
        # the finger lifts: the mouse simply stops reporting
        last = self.t - DT
        self.eng.idle(last + 0.03)
        self.assertTrue(self.eng.scrolling, "a 30 ms gap is a Bluetooth hiccup, not a lift")
        self.eng.idle(last + mmd.LIFT_SILENCE + 0.001)
        self.assertFalse(self.eng.scrolling)
        self.assertTrue(self.eng.coasting, "a flick that lifts must keep gliding")

    def loop(self, start, end):
        """The main loop between reports: idle() and tick() every TICK; scroll per pass."""
        out, t = [], start
        while t < end:
            t += mmd.TICK
            before = self.wheel()
            self.eng.idle(t)
            if self.eng.coasting:
                self.eng.tick(t)
            out.append(self.wheel() - before)
        return out

    def test_lift_does_not_show_in_the_speed(self):
        self.stroke(10)
        before, t0 = self.wheel(), self.t
        self.stroke(15, y0=100)
        finger = (self.wheel() - before) / (self.t - t0) * mmd.TICK  # per loop pass
        last = self.t - DT
        passes = self.loop(last, last + 0.15)  # lift: the mouse goes silent
        self.assertTrue(self.eng.coasting)
        # the finger itself only reports every 11 ms, so one empty 8 ms pass is normal;
        # two in a row would be a visible stall while the lift is being detected
        stalls = [i for i in range(12) if passes[i] == 0 and passes[i + 1] == 0]
        self.assertEqual(stalls, [], f"the page must not pause at the lift: {passes[:12]}")
        early = sum(passes[1:10]) / 9
        self.assertAlmostEqual(early, finger, delta=0.25 * abs(finger), msg="the glide carries on at the finger's speed")

    def test_late_report_is_not_counted_twice(self):
        steady = ScrollLiftCase("test_late_report_is_not_counted_twice")
        steady.setUp()
        for case, gap in ((self, True), (steady, False)):
            y = case.stroke(20)
            if gap:  # one report arrives 35 ms late; the loop bridges the gap
                case.loop(case.t - DT, case.t - DT + 0.035)
                case.t += 0.035 - DT
            case.stroke(10, y0=y)
        self.assertTrue(self.eng.scrolling)
        self.assertAlmostEqual(self.wheel(), steady.wheel(), delta=mmd.HIRES,
                               msg="the bridged distance comes off the late report")

    def test_finger_that_stops_before_lifting_does_not_glide(self):
        y = self.stroke(25)
        for _ in range(30):  # finger holds still for ~330 ms, then lifts
            self.report([(0, 1, -600, y)])
        self.lift()
        self.assertFalse(self.eng.scrolling)
        self.assertFalse(self.eng.coasting)

    def test_tracking_id_flicker_keeps_the_scroll(self):
        y = self.stroke(15)
        touch = self.eng.touches[1]
        # the same finger comes back under a new tracking id, a little farther on
        self.report([(0, 2, -600, y)])
        self.assertTrue(self.eng.scrolling)
        self.assertEqual(self.eng.primary, (2,))
        self.assertIs(self.eng.touches[2], touch, "the re-detected finger keeps its history")
        before = self.wheel()
        self.stroke(10, y0=y - 40, tid=2)
        self.assertNotEqual(self.wheel(), before, "scrolling continues without a new start threshold")

    def test_flicker_before_the_scroll_starts_does_not_reset_the_threshold(self):
        # a finger re-reported under a new tracking id on every report still starts a scroll
        y = 500
        for tid in range(10, 40):
            self.report([(0, tid, -600, y)])
            y -= 40
        self.assertTrue(self.eng.scrolling)

    def test_resting_finger_does_not_take_over_a_lifted_scroll(self):
        resting = [(1, 7, 950, -500)]  # ring finger resting near the right side
        self.report(resting)
        self.stroke(25, extra=resting)
        self.assertTrue(self.eng.scrolling)
        # the scrolling finger lifts; only the resting finger is still reported
        self.report(resting)
        self.assertFalse(self.eng.scrolling, "a far-away resting finger is not the scrolling finger")
        self.assertTrue(self.eng.coasting)

    def glide(self):
        """One flick and lift; returns the glide velocity."""
        self.stroke(25)
        self.lift()
        self.assertTrue(self.eng.coasting)
        self.t += 0.15
        return self.eng.c_vel

    def test_same_direction_rescroll_keeps_the_glide_speed(self):
        v1 = self.glide()
        before = self.wheel()
        self.stroke(25, tid=3)  # the next flick, same way, same speed
        self.assertTrue(self.eng.scrolling)
        self.assertTrue(self.eng.coasting, "the glide keeps going under a same-way stroke")
        self.assertEqual(self.wheel(), before, "the glide moves the page; the stroke doesn't add on top")
        self.assertGreaterEqual(abs(self.eng.c_vel), abs(v1), "no slowdown while the stroke rides on the glide")
        self.lift()
        self.assertTrue(self.eng.coasting)
        self.assertGreaterEqual(abs(self.eng.c_vel), abs(v1), "the glide starts over from the speed it held")
        self.assertLess(abs(self.eng.c_vel), 1.5 * abs(v1), "a same-speed stroke keeps the speed, it doesn't stack")

    def test_slowing_down_at_the_end_of_a_carried_stroke_keeps_the_glide(self):
        v1 = self.glide()
        y = self.stroke(20, tid=3)
        for dy in (-30, -30, -20, -20, -10, -10, -5, -5, -2, -2):  # the finger eases off, then lifts
            self.report([(0, 3, -600, y)])
            y += dy
        self.assertTrue(self.eng.coasting)
        self.lift()
        self.assertTrue(self.eng.coasting, "easing off before the lift must not cut the glide")
        self.assertGreaterEqual(abs(self.eng.c_vel), abs(v1))

    def test_carried_stroke_that_rests_holds_the_page(self):
        self.glide()
        y = self.stroke(25, tid=3)
        self.assertTrue(self.eng.coasting)
        for _ in range(45):  # the finger rests on the surface for ~500 ms
            self.report([(0, 3, -600, y)])
        self.assertFalse(self.eng.coasting, "a resting finger holds the page instead of riding the glide")

    def test_opposite_scroll_stops_a_glide(self):
        self.glide()
        self.stroke(25, y0=-500, dy=40, tid=3)
        self.assertTrue(self.eng.scrolling)
        self.assertFalse(self.eng.coasting)

    def test_finger_resting_on_a_glide_stops_it(self):
        self.glide()
        for _ in range(12):  # a finger lands and holds still for ~130 ms
            self.report([(0, 3, -600, 0)])
        self.assertFalse(self.eng.coasting)

    def test_finger_landing_where_the_last_stroke_ended_is_a_new_touch(self):
        y = self.stroke(25)
        self.lift()
        self.t += 0.25
        self.assertTrue(self.eng.coasting)
        for _ in range(12):  # lands right where the flick lifted, and holds
            self.report([(0, 3, -600, y + 40)])
        self.assertNotIn(1, [tid for tid, _ in self.eng.vanished])
        self.assertFalse(self.eng.coasting, "a finger that lifted 250 ms ago is not a flicker")


if __name__ == "__main__":
    unittest.main()
