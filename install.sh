#!/usr/bin/env bash
# omarchy-magic-mouse installer. Safe to re-run.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
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

say "udev rules + driver option (needs your password): /etc/udev/rules.d/70-magic-mouse.rules, /etc/modprobe.d/hid_magicmouse.conf"
if [ -t 0 ]; then sudo "$here/install-root.sh"; else pkexec "$here/install-root.sh"; fi
relogin=0
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
  say "adding $USER to the input group"
  sudo usermod -aG input "$USER"; relogin=1
fi

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

if [ "$relogin" = 1 ]; then
  say "You were added to the 'input' group: log out and back in once, then the daemon can see the mouse."
fi
say "done. Tune ~/.config/magic-mouse/config.toml (applies live). Logs: journalctl --user -u magic-mouse -f"
