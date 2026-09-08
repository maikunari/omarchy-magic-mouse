#!/usr/bin/env bash
# Privileged part of the omarchy-magic-mouse install. Run via sudo or pkexec.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -Dm644 "$here/config/70-magic-mouse.rules" /etc/udev/rules.d/70-magic-mouse.rules
install -Dm644 "$here/config/hid_magicmouse.conf" /etc/modprobe.d/hid_magicmouse.conf
udevadm control --reload
udevadm trigger --subsystem-match=hidraw --subsystem-match=misc --subsystem-match=input --action=add || true
if [ -e /sys/module/hid_magicmouse/parameters/emulate_3button ]; then
  echo 0 > /sys/module/hid_magicmouse/parameters/emulate_3button
fi
echo "root steps done"
