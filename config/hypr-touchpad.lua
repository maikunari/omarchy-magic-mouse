
-- omarchy-magic-mouse, scroll.output = "touchpad": scrolls arrive through this
-- virtual touchpad. The daemon already sets direction, speed and ramp; the pad
-- moves 1:1 with the finger so libinput starts scrolls like a real touchpad,
-- and scroll_factor brings that to the same speed as the wheel output.
hl.device({
  name = "magic-mouse-omarchy-touchpad",
  sensitivity = 0,
  accel_profile = "flat",
  natural_scroll = false,
  scroll_factor = 0.12,
  tap_to_click = false,
  disable_while_typing = false,
})
