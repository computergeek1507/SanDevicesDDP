{{
  APA102_Pin_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Toggles ONLY the J1 data (P0) and clock (P21)
  pins together, once per second, forever - nothing else, no W5200, no DDP, no PASM timing tricks.

  Purpose: isolate whether this firmware can drive these two specific pins at all, separate from the much more
  complex PixelDriver_E6804.spin PASM. A 1Hz toggle is slow enough to see with just a multimeter on DC volts
  (watch it flip between ~0V and ~3.3V once a second) or a basic LED+resistor clipped between the pin and ground -
  no oscilloscope/logic analyzer needed.

  If you see steady 1Hz toggling on BOTH pins: GPIO control of J1's data/clock is fine, so the APA102-white-at-
  power-up symptom with the real firmware points at a bug in PixelDriver_E6804.spin's PASM logic/timing instead.
  If you see NO toggling on one or both pins: something more basic is wrong (wrong pin number, a short, or a
  dead Propeller I/O driver on that pin) - narrow it down pin by pin before looking at the real driver again.
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  PIN_DATA_J1 = 0                        ' per docs/pin_mapping_E6804.md
  PIN_CLK_J1  = 21

PUB Main
  dira[PIN_DATA_J1]~~
  dira[PIN_CLK_J1]~~
  repeat
    outa[PIN_DATA_J1]~~
    outa[PIN_CLK_J1]~~
    waitcnt(clkfreq + cnt)
    outa[PIN_DATA_J1]~
    outa[PIN_CLK_J1]~
    waitcnt(clkfreq + cnt)
