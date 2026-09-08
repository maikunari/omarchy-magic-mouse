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

- **Battery and settings in the bar:** a small Omarchy shell widget shows the
  mouse's charge and highlights when low. Click it for a settings popup with
  tracking speed, natural scrolling, scroll speed, momentum and gesture
  switches; every control applies live. Right-click opens the Bluetooth panel.
  The daemon asks the mouse for its charge directly (the mouse only volunteers
  it to the kernel on its own schedule, so UPower alone shows 0% for a long
  time after connecting).
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
| Swipe between full-screen apps (two fingers) | workspace switch (`hl.dsp.focus({ workspace = "e+1" })`) |
| Mission Control (two-finger double tap) | hook, off by default |
| Smart zoom (one-finger double tap) | hook, off by default |
| Battery level | bar widget (`io.github.maikunari.magic-mouse`) |
| Force click, Handoff | not applicable |

## Install

This repo is an Omarchy plugin (the bar widget and settings popup) that ships
its own helper daemon. Two steps:

```sh
# 1. the plugin: clones into ~/.config/omarchy/plugins/ and enables the bar widget
omarchy plugin add https://github.com/maikunari/omarchy-magic-mouse --enable

# 2. the daemon, udev rule, driver option and Hyprland snippet (asks for your password once)
~/.config/omarchy/plugins/io.github.maikunari.magic-mouse/install.sh
```

Later updates: `omarchy plugin update io.github.maikunari.magic-mouse`, then
re-run `install.sh` to refresh the daemon.

Prefer a plain checkout? `git clone` anywhere and run `./install.sh`; it copies
the widget into the plugins directory for you.

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

Click the mouse icon in the bar for the common settings. Everything else is in
`~/.config/magic-mouse/config.toml`; changes apply live, no restart. From a
shell, `magic-mouse-config set pointer.tracking_speed=1.0` edits the file
without disturbing your comments, and `magic-mouse-config get` prints the
effective config as JSON.

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

## Remove

```sh
~/.config/omarchy/plugins/io.github.maikunari.magic-mouse/uninstall.sh   # daemon, unit, udev rule, driver option
omarchy plugin remove io.github.maikunari.magic-mouse                     # the widget
```

`uninstall.sh` leaves `~/.config/magic-mouse/config.toml` and the small
`magic-mouse-omarchy` device block in your Hyprland input config; delete those
by hand if you want a clean slate.

## What the installer touches

Everything is listed so you can decide before running it:

| Path | What |
|---|---|
| `~/.local/bin/magic-mouse-daemon`, `magic-mouse-config`, `magic-mouse-battery-query` | the daemon and its two helpers |
| `~/.config/systemd/user/magic-mouse.service` | user service, enabled and started |
| `~/.config/magic-mouse/config.toml` | your settings (only created if missing) |
| `~/.config/hypr/input.lua` (or `input.conf`) | a 7-line device block, **appended only after asking**, with a backup |
| `/etc/udev/rules.d/70-magic-mouse.rules` | via sudo/pkexec: lets your user read the mouse's input and raw HID nodes |
| `/etc/modprobe.d/hid_magicmouse.conf` | via sudo/pkexec: `emulate_3button=0` |

No sudoers changes, no NOPASSWD, nothing downloaded at install time. The
daemon runs as your user, talks only to the local mouse and the Hyprland
socket, and writes its status under `$XDG_RUNTIME_DIR/magic-mouse/`.

## Dependencies

- `python-evdev` (Arch package; the installer adds it with `omarchy pkg add`)
- the in-kernel `hid_magicmouse` driver (ships with Arch) and `upower` (ships with Omarchy)
- Omarchy shell for the bar widget; the daemon works on any Hyprland

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
