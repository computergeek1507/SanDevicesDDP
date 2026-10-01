{{
  Blink_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Blinks the E6804's green status LED (P16, per
  docs/pin_mapping_E6804.md) about twice a second. Nothing else - no Ethernet, no pixels, no dependencies on any
  other file in this repo.

  Purpose: confirm the Prop Plug and the board's PROGRAM port (J20) are wired up correctly, and that Propeller
  Tool can talk to the board, BEFORE trusting anything else in this repo. Load this with Propeller Tool's
  "Run" (F10) - RAM only, non-persistent - NOT "Load EEPROM" (F11/F8). RAM-only means a power cycle reverts to
  whatever's already in the board's EEPROM (the stock SanDevices firmware, untouched), so this is a fully
  reversible test with zero risk to the board's existing firmware.

  Expected result: green LED starts blinking within ~2 seconds of clicking Run. If Propeller Tool instead reports
  "Prop CPU not found" or similar, check the Prop Plug is fully seated in J20, oriented per the silkscreen's Vss
  marking (SanDevices' documentation notes it can't be damaged by plugging in backwards, just won't work), and
  that the board is powered.
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000                   ' 5MHz crystal, matches E6804 per docs/NOTES.md

  LED_GREEN = 16                         ' per docs/pin_mapping_E6804.md

PUB Main
  dira[LED_GREEN]~~
  repeat
    !outa[LED_GREEN]
    waitcnt(clkfreq / 2 + cnt)
