{{
  Pin_Range_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Toggles P0 through P15 ALL TOGETHER, once per
  second, forever - no PASM, no timing tricks, just plain dira/outa on a 16-bit mask.

  Purpose: after two different pixel driver implementations (APA102 clocked, WS2812 single-wire) both showed
  complete darkness on P0, this widens the test to a whole range of pins at once. Probe any pin from P0 to P15 with
  a multimeter (DC volts) or a clipped-on LED+resistor - all of them should flip between ~0V/off and ~3.3V/on once
  a second, together. If P0 specifically doesn't toggle but others do, that's a P0-specific problem (bad trace,
  bad connection, or dead I/O driver on that one pin). If NONE of them toggle, something more fundamental is wrong
  (compile/upload not actually running, wrong clock config, etc.) - worth comparing against test/Blink_Test.spin
  (P16), which is already confirmed working.
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

PUB Main
  dira := %0000_0000_0000_0000_1111_1111_1111_1111     ' P0-P15 as outputs
  repeat
    outa := %0000_0000_0000_0000_1111_1111_1111_1111   ' all high
    waitcnt(clkfreq + cnt)
    outa := 0                                          ' all low
    waitcnt(clkfreq + cnt)
