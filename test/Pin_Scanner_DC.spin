{{
  Pin_Scanner_DC.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. For each pin P0 through P15, in order: blinks the
  green status LED (P16) (pinIdx + 1) times - 1 blink = P0, 2 blinks = P1, ... 16 blinks = P15 - then holds that
  pin STEADY HIGH (plain DC, no WS2812/timing protocol at all) for ~3 seconds, then moves to the next pin. Repeats
  forever.

  Purpose: simplest possible per-pin identification test. A steady DC-high pin is much easier to catch with a
  multimeter than a fast WS2812 pulse train (see test/WS2812_Pin_Scanner.spin for that version) - use this one for
  a quick "which pin is actually P0 on this board" check, counting green blinks to know which pin is about to go
  high.
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  LED_PIN  = 16                  ' green status LED, per docs/pin_mapping_E6804.md

PUB Main
  cognew(@entry, 0)
  repeat                         ' main Spin cog has nothing else to do - the PASM cog does everything

DAT
                        org     0

entry                   rdlong  sysClk, #0              ' hub address 0 holds CLKFREQ, set by the boot process
                        mov     blinkDelay, sysClk
                        shr     blinkDelay, #2          ' sysClk/4 = 0.25s per half-blink (exact, since 4 = 2^2)

                        mov     holdDelay, sysClk       ' holdDelay = 3 x sysClk = ~3 seconds (no multiply on P1,
                        add     holdDelay, sysClk       ' so just add sysClk to itself twice)
                        add     holdDelay, sysClk

                        mov     pinIdx, #0

pinLoop                 mov     ledMask, #1
                        shl     ledMask, #LED_PIN
                        mov     dira, ledMask
                        mov     outa, #0

                        mov     blinkCnt, pinIdx
                        add     blinkCnt, #1            ' blink (pinIdx + 1) times - pin 0 is 1 blink, not 0
:blinkLoop              or      outa, ledMask
                        mov     time, cnt
                        add     time, blinkDelay
                        waitcnt time, #0
                        andn    outa, ledMask
                        mov     time, cnt
                        add     time, blinkDelay
                        waitcnt time, #0
                        djnz    blinkCnt, #:blinkLoop

                        mov     curMask, #1
                        shl     curMask, pinIdx
                        mov     dira, curMask           ' only this pin driven - all others released
                        mov     outa, curMask           ' steady HIGH - plain DC, easy to read with a multimeter

                        mov     time, cnt
                        add     time, holdDelay
                        waitcnt time, #0

                        add     pinIdx, #1
                        cmp     pinIdx, #16       wz
              if_z      mov     pinIdx, #0
                        jmp     #pinLoop

sysClk                  res     1
blinkDelay              res     1
holdDelay               res     1
pinIdx                  res     1
ledMask                 res     1
curMask                 res     1
blinkCnt                res     1
time                    res     1

                        fit     496
