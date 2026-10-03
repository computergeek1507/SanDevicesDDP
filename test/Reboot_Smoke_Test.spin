{{
  Reboot_Smoke_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Confirms FlexSpin's REBOOT keyword actually works
  for this P1 (P8X32A) target before HTTPServer.spin relies on it to apply saved config. Blinks the green LED a
  few times, then REBOOTs - if REBOOT works, the blink sequence should repeat forever (the chip restarts and runs
  this same program again from the top, exactly like a power cycle). If REBOOT isn't supported/behaves differently
  on this target, expect either a compile error or the LED blinking once and then hanging/not repeating.
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  LED_PIN = 16          ' green status LED, per docs/pin_mapping_E6804.md

PUB Main | i
  dira[LED_PIN]~~
  repeat i from 0 to 4
    outa[LED_PIN]~~
    waitcnt(clkfreq / 4 + cnt)
    outa[LED_PIN]~
    waitcnt(clkfreq / 4 + cnt)

  waitcnt(clkfreq + cnt)
  REBOOT
