
-- omarchy-magic-mouse: the daemon does acceleration, scrolling and momentum
-- itself, so Hyprland/libinput must stay out of the way for the virtual device.
hl.device({
  name = "magic-mouse-omarchy",
  sensitivity = 0,
  accel_profile = "flat",
  natural_scroll = false,
})
