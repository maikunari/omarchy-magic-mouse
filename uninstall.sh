#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now magic-mouse.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/magic-mouse.service" "$HOME/.local/bin/magic-mouse-daemon"
systemctl --user daemon-reload
omarchy plugin disable io.github.maikunari.magic-mouse 2>/dev/null || true
rm -rf "$HOME/.config/omarchy/plugins/io.github.maikunari.magic-mouse"
sudo rm -f /etc/udev/rules.d/70-magic-mouse.rules /etc/modprobe.d/hid_magicmouse.conf && sudo udevadm control --reload
echo "removed daemon, unit, udev rule, driver options and the bar widget."
echo "kept: ~/.config/magic-mouse/config.toml and the 'omarchy-magic-mouse' block in ~/.config/hypr/input.lua (delete by hand if you like)."
