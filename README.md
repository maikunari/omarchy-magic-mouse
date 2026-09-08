# omarchy-magic-mouse

Make an Apple Magic Mouse feel like it does on a Mac, on [Omarchy](https://omarchy.org)
(Hyprland / Wayland). Pointer acceleration that slows down for small targets,
scrolling that only happens when you mean it, natural direction, and momentum.

## Why the stock experience is bad

The kernel `hid_magicmouse` driver exposes the mouse as a plain pointer plus
an "emulated scroll wheel" derived from the touch surface. Three things follow:

- **The page scrolls while you aim.** Any finger drift on the glass becomes
  wheel events. There is no start threshold, so as you slow down to click, the
  page moves under you.
- **The cursor jumps past small targets.** Bluetooth delivers some reports in
  bursts. libinput turns a burst into a huge instantaneous velocity, and every
  acceleration profile then multiplies that frame.
- **Scroll direction and momentum are wrong or missing.**

## What this does

A small daemon grabs the real mouse and re-emits a virtual one called
`magic-mouse-omarchy`:

- **Pointer:** Apple's own acceleration curve, taken from the open-source
  IOHIDFamily driver, driven by the same "tracking speed" number as the macOS
  slider. Velocity is smoothed so Bluetooth bursts can't spike it. Click
  tolerance freezes the cursor for a moment after a press so the click itself
  can't nudge it.
- **Scroll:** synthesized from the touch surface, ignoring the kernel wheel.
  A finger must travel about a millimetre before a scroll starts, and a scroll
  can't start until the pointer has been still for a moment (drift happens while
  you're still aiming; real scrolls happen after the hand stops). One axis at a
  time, natural direction, and the scroll rate ramps with finger speed.
- **Momentum:** flick and lift, the page glides and eases out.
- **Clicks:** the kernel driver's centre "middle-click" zone (which pastes on
  Linux) is a left click, like on a Mac. Configurable.
- **Gestures:** one-finger sideways flick = back / forward (browser buttons).
  Two-finger sideways swipe = previous / next workspace. One- and two-finger
  double taps are hooks you can point at any Hyprland dispatcher or command.

- **Battery in the bar:** a small Omarchy shell widget shows the mouse's charge,
  highlights when low, and opens the Bluetooth panel on click. The daemon asks
  the mouse directly (the mouse only volunteers its level to the kernel on its
  own schedule, so UPower alone shows 0% for a long time after connecting).
- **Clicks decided by the mouse:** the kernel driver's three fixed touch zones
  (left / middle / right) are turned off, so the mouse's own firmware decides
  left vs right, exactly as on macOS.

Hyprland only needs a flat profile for the virtual device; the installer adds it.

## macOS feature checklist

| macOS | Here |
|---|---|
| Pointer acceleration | Apple's curve, same numbers |
| Natural scrolling | yes |
| Scroll starts only when you mean it | start threshold + settle rule |
| Momentum scrolling | yes (`momentum.decay` 0.984 matches Apple's rate) |
| Secondary click on the right side | done by the mouse itself |
| No middle click | `buttons.middle = "left"` |
| Swipe between pages (one finger) | back / forward buttons |
| Swipe between full-screen apps (two fingers) | workspace switch |
| Mission Control (two-finger double tap) | hook, off by default |
| Smart zoom (one-finger double tap) | hook, off by default |
| Battery level | bar widget (`io.github.maikunari.magic-mouse`) |
| Force click, Handoff | not applicable |

## Install

```sh
git clone https://github.com/maikunari/omarchy-magic-mouse
cd omarchy-magic-mouse
./install.sh
```

Pair the mouse with Bluetooth as usual. The daemon waits for it and grabs it
whenever it connects. If the installer added you to the `input` group, log out
and back in once.

Check it is running:

```sh
systemctl --user status magic-mouse
journalctl --user -u magic-mouse -f
hyprctl devices | grep magic-mouse-omarchy
```

## Tune it

Edit `~/.config/magic-mouse/config.toml`. Changes apply live, no restart.

| Feels like… | Change |
|---|---|
| pointer too slow / too fast | `pointer.tracking_speed`, same scale as the macOS slider (0 to 3, Apple default 0.6875) |
| the curve is right but everything is a touch off | `pointer.speed` 0.9 / 1.1 |
| scroll starts when I only meant to click | raise `scroll.start_mm` (1.2) or `scroll.settle_ms` (250) |
| have to move the finger too far before it scrolls | lower `scroll.start_mm` (0.5) |
| scrolling backwards | flip `scroll.natural` |
| forward/back inverted only on my model | flip `scroll.invert_y` |
| glide too long / too short | `momentum.decay` 0.95 / 0.985 |
| no glide | `momentum.enabled = false` |

## Uninstall

```sh
./uninstall.sh
```

## Notes

- Works with Magic Mouse 1 (`05ac:030d`) and Magic Mouse 2 / USB‑C (`004c:0269`),
  matched by ID, so it does not matter what you named the mouse on macOS.
- Requires `python-evdev` (installed by `install.sh`) and the in-kernel
  `hid_magicmouse` driver, which Arch ships.
- The installer writes `/etc/modprobe.d/hid_magicmouse.conf` with
  `emulate_3button=0`. The old `scroll_acceleration` / `scroll_speed` options
  only affect the kernel's emulated wheel, which this daemon ignores.
- Bar widget settings (on its entry in `~/.config/omarchy/shell.json`):
  `"match": "MMM"` to pin it to one device by model name, `"lowAt": 20` for the
  low-battery highlight threshold.
