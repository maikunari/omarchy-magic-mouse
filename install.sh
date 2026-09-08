#!/usr/bin/env bash
# omarchy-magic-mouse installer. Safe to re-run.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if ! python3 -c 'import evdev' 2>/dev/null; then
  say "installing python-evdev"
  if command -v omarchy >/dev/null 2>&1; then omarchy pkg add python-evdev; else sudo pacman -S --needed --noconfirm python-evdev; fi
fi

say "daemon -> ~/.local/bin/magic-mouse-daemon"
install -Dm755 "$here/bin/magic-mouse-daemon" "$HOME/.local/bin/magic-mouse-daemon"
install -Dm644 "$here/config/magic-mouse.service" "$HOME/.config/systemd/user/magic-mouse.service"
if [ ! -f "$HOME/.config/magic-mouse/config.toml" ]; then
  install -Dm644 "$here/config/config.toml" "$HOME/.config/magic-mouse/config.toml"
  say "config -> ~/.config/magic-mouse/config.toml"
fi

say "udev rules + driver options (needs your password)"
if [ -t 0 ]; then sudo "$here/install-root.sh"; else pkexec "$here/install-root.sh"; fi
relogin=0
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
  say "adding $USER to the input group"
  sudo usermod -aG input "$USER"; relogin=1
fi

hypr_lua="$HOME/.config/hypr/input.lua"; hypr_conf="$HOME/.config/hypr/input.conf"
marker="omarchy-magic-mouse"
if [ -f "$hypr_lua" ] && grep -q 'require("hypr.input")' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null; then
  grep -q "$marker" "$hypr_lua" || { cat "$here/config/hypr-input.lua" >> "$hypr_lua"; say "Hyprland snippet appended to $hypr_lua"; }
elif [ -f "$hypr_conf" ]; then
  grep -q "$marker" "$hypr_conf" || { cat "$here/config/hypr-input.conf" >> "$hypr_conf"; say "Hyprland snippet appended to $hypr_conf"; }
else
  say "WARNING: no ~/.config/hypr/input.lua or input.conf found; add config/hypr-input.lua yourself"
fi
if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprctl reload >/dev/null || true
  errs="$(hyprctl configerrors 2>/dev/null || true)"
  [ -z "$errs" ] || { echo "$errs"; say "WARNING: Hyprland reported config errors above"; }
fi

plugin_id="io.github.maikunari.magic-mouse"
if command -v omarchy-shell >/dev/null 2>&1; then
  say "bar widget (mouse battery) -> ~/.config/omarchy/plugins/$plugin_id"
  rm -rf "$HOME/.config/omarchy/plugins/$plugin_id"
  cp -r "$here/plugin" "$HOME/.config/omarchy/plugins/$plugin_id"
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
