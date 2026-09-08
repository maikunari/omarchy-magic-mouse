#!/usr/bin/env bash
# omarchy-magic-mouse installer. Safe to re-run.
#
# Privilege model: nothing from this checkout is ever executed as root. The two
# files written under /etc are fixed text embedded below; root only runs the
# distro-owned tee / udevadm / modprobe binaries with fixed arguments, and the
# installer verifies what landed against the embedded text before going on.
# Access to the mouse comes from the device-specific uaccess udev rule alone:
# the installer never changes group membership, and stops if the rule did not
# take effect.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m==> error:\033[0m %s\n' "$*" >&2; exit 1; }
ASSUME_YES=0
for arg in "$@"; do case "$arg" in --yes|-y) ASSUME_YES=1 ;; -h|--help) echo "Usage: ./install.sh [--yes]"; exit 0 ;; esac; done
ask() {  # ask "question" -> 0 for yes
  (( ASSUME_YES )) && return 0
  if [ -t 0 ]; then read -r -p "$1 [Y/n] " a; [[ -z $a || $a =~ ^[Yy] ]]; else return 0; fi
}

if ! python3 -c 'import evdev' 2>/dev/null; then
  say "installing python-evdev"
  if command -v omarchy >/dev/null 2>&1; then omarchy pkg add python-evdev; else sudo pacman -S --needed --noconfirm python-evdev; fi
fi

say "daemon -> ~/.local/bin/magic-mouse-daemon"
install -Dm755 "$here/bin/magic-mouse-daemon" "$HOME/.local/bin/magic-mouse-daemon"
install -Dm755 "$here/bin/magic-mouse-config" "$HOME/.local/bin/magic-mouse-config"
install -Dm755 "$here/bin/magic-mouse-battery-query" "$HOME/.local/bin/magic-mouse-battery-query"
install -Dm644 "$here/config/magic-mouse.service" "$HOME/.config/systemd/user/magic-mouse.service"
if [ ! -f "$HOME/.config/magic-mouse/config.toml" ]; then
  install -Dm644 "$here/config/config.toml" "$HOME/.config/magic-mouse/config.toml"
  say "config -> ~/.config/magic-mouse/config.toml"
fi

# ---------------------------------------------------------------------------
# Root step. The exact content of both files, so it can be reviewed here.
# ---------------------------------------------------------------------------
udev_path=/etc/udev/rules.d/70-magic-mouse.rules
modprobe_path=/etc/modprobe.d/hid_magicmouse.conf
udev_rules=$(cat <<'RULES'
# omarchy-magic-mouse: grant the logged-in user access to the Magic Mouse and to
# uinput (for the virtual mouse) via logind's per-seat uaccess ACL. No group
# changes, no world-readable nodes; only these device IDs.
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="004c", ATTRS{id/product}=="0269", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="004c", ATTRS{id/product}=="030d", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="05ac", ATTRS{id/product}=="030d", TAG+="uaccess"
# Raw HID node too, so the daemon can ask the mouse for its battery level.
SUBSYSTEM=="hidraw", KERNELS=="0005:004C:0269.*", TAG+="uaccess"
SUBSYSTEM=="hidraw", KERNELS=="0005:05AC:030D.*", TAG+="uaccess"
RULES
)
modprobe_conf=$(cat <<'CONF'
# omarchy-magic-mouse: let the mouse's own firmware decide left vs right click
# (like macOS) instead of the driver's three fixed touch zones, which also
# invent a middle button that macOS never had.
options hid_magicmouse emulate_3button=0
CONF
)

[ -t 0 ] || die "the root step uses sudo and needs a terminal: run ./install.sh from an interactive shell inside your desktop session"
for p in "$udev_path" "$modprobe_path"; do
  [ -L "$p" ] && die "$p is a symlink; refusing to write through it"
done
say "root step (needs your password): tee -> $udev_path, $modprobe_path; udevadm reload"
printf '%s\n' "$udev_rules"    | sudo tee "$udev_path" >/dev/null
printf '%s\n' "$modprobe_conf" | sudo tee "$modprobe_path" >/dev/null
cmp -s <(printf '%s\n' "$udev_rules")    "$udev_path"     || die "$udev_path does not match the rules embedded in install.sh"
cmp -s <(printf '%s\n' "$modprobe_conf") "$modprobe_path" || die "$modprobe_path does not match the text embedded in install.sh"
[ -e /dev/uinput ] || sudo modprobe uinput
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=misc --subsystem-match=input --subsystem-match=hidraw --action=add || true  # the ACL check below is the real gate
if [ -e /sys/module/hid_magicmouse/parameters/emulate_3button ]; then
  echo 0 | sudo tee /sys/module/hid_magicmouse/parameters/emulate_3button >/dev/null
fi

# Fail closed: the uaccess ACL must actually have reached the device nodes.
acl_help="uaccess ACLs are granted by systemd-logind to the active seat session. Run install.sh from a terminal inside your Hyprland session (not over SSH), and check: getfacl /dev/uinput"
[ -r /dev/uinput ] && [ -w /dev/uinput ] || die "your user cannot open /dev/uinput after installing the udev rule. $acl_help"
for dev in /sys/class/input/event*; do
  [ -e "$dev/device/id/vendor" ] || continue
  vid=$(<"$dev/device/id/vendor"); pid=$(<"$dev/device/id/product")
  case "$vid:$pid" in
    004c:0269|004c:030d|05ac:030d)
      node="/dev/input/${dev##*/}"
      [ -r "$node" ] || die "your user cannot read $node (the Magic Mouse) after installing the udev rule. $acl_help"
      ;;
  esac
done
say "device access OK (uaccess ACL on /dev/uinput and the mouse)"

hypr_lua="$HOME/.config/hypr/input.lua"; hypr_conf="$HOME/.config/hypr/input.conf"
marker="omarchy-magic-mouse"
hypr_target=""; hypr_snippet=""
if [ -f "$hypr_lua" ] && grep -q 'require("hypr.input")' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null; then
  hypr_target="$hypr_lua"; hypr_snippet="$here/config/hypr-input.lua"
elif [ -f "$hypr_conf" ]; then
  hypr_target="$hypr_conf"; hypr_snippet="$here/config/hypr-input.conf"
fi
if [ -z "$hypr_target" ]; then
  say "WARNING: no ~/.config/hypr/input.lua or input.conf found; add config/hypr-input.lua yourself"
elif grep -q "$marker" "$hypr_target"; then
  say "Hyprland snippet already present in $hypr_target"
elif ask "Append the 7-line 'magic-mouse-omarchy' device block to $hypr_target? (needed so Hyprland doesn't re-accelerate the pointer)"; then
  cp "$hypr_target" "$hypr_target.bak.magic-mouse.$(date +%s)"
  cat "$hypr_snippet" >> "$hypr_target"
  say "Hyprland snippet appended to $hypr_target (backup written beside it)"
else
  say "Skipped. Add the block from $hypr_snippet to your Hyprland input config by hand."
fi
if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprctl reload >/dev/null || true
  errs="$(hyprctl configerrors 2>/dev/null || true)"
  [ -z "$errs" ] || { echo "$errs"; say "WARNING: Hyprland reported config errors above"; }
fi

plugin_id="io.github.maikunari.magic-mouse"
plugins_dir="$HOME/.config/omarchy/plugins"
if command -v omarchy-shell >/dev/null 2>&1; then
  if [ "$here" = "$plugins_dir/$plugin_id" ]; then
    say "bar widget: running from the installed plugin checkout, nothing to copy"
  elif [ -d "$plugins_dir/$plugin_id/.git" ]; then
    say "bar widget: git-managed copy already installed (update it with: omarchy plugin update $plugin_id)"
  else
    say "bar widget -> $plugins_dir/$plugin_id"
    rm -rf "$plugins_dir/$plugin_id"
    mkdir -p "$plugins_dir/$plugin_id"
    cp -r "$here/manifest.json" "$here/BarWidget.qml" "$here/Panel.qml" "$here/README.md" "$here/LICENSE" "$plugins_dir/$plugin_id/"
    [ -f "$here/preview.png" ] && cp "$here/preview.png" "$plugins_dir/$plugin_id/"
  fi
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  sleep 1
  if ! grep -q "$plugin_id" "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
    omarchy plugin enable "$plugin_id" --section right >/dev/null 2>&1 || say "WARNING: could not enable the bar widget; try: omarchy plugin enable $plugin_id --section right"
  fi
fi

say "enabling magic-mouse.service (user)"
systemctl --user daemon-reload
systemctl --user enable --now magic-mouse.service
sleep 1
systemctl --user --no-pager --lines=5 status magic-mouse.service || true

say "done. Tune ~/.config/magic-mouse/config.toml (applies live). Logs: journalctl --user -u magic-mouse -f"
