{{
  WS2812_Pin_Scanner.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Cycles through P0 through P15, one at a time,
  holding each for a few seconds while continuously sending a valid single-pixel WS2812 frame (red) on it, then
  moving to the next pin. Repeats forever.

  Purpose: combines two things we haven't tested together yet - real WS2812 bit timing (not just a DC toggle) AND
  a scan across many candidate pins (not just P0). Move your WS2812 pixel's data wire to each pin in turn (or use
  several probes/LEDs if you have them) and watch for red. This uses the exact same bit-timing technique as
  PixelDriver_E6804.spin's byteloop/bitloop (proven-through by hand-trace), just specialized for one pin instead of
  four in parallel - if a pixel lights up red on ANY of these pins, the WS2812 encoding logic itself is confirmed
  correct, and whichever pin(s) DON'T light it up point at pin-specific wiring problems instead. If NONE of them
  light it up, the bug is in the timing/encoding logic itself (or the pixel's power/ground), not pin selection.

  WS2812 chips expect bytes in GREEN, RED, BLUE order on the wire (not RGB) - this test sends them in that order
  directly, unlike PixelDriver_E6804.spin / DDP_Parser.spin which currently pass bytes through in whatever order
  they're given (a separate, known, not-yet-fixed issue - see docs/NOTES.md).

  Before each pin's test window, the board's red status LED (P17) blinks (pinIdx + 1) times - e.g. 1 blink = P0,
  5 blinks = P4, 16 blinks = P15 - so you can identify exactly which pin is under test just by counting blinks,
  without needing to time the cycle precisely.
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  LED_PIN        = 17            ' red status LED, per docs/pin_mapping_E6804.md

  ' WS2812/WS2812B (800kHz-class) bit timing at 80MHz core clock - same constants as PixelDriver_E6804.spin
  BIT_PERIOD_CYC = 100
  T0H_CYC        = 32
  T1H_CYC        = 64
  RESET_CYC      = 4800          ' 60us latch gap between frames
  HOLD_REPEATS   = 25000         ' ~2.5s per pin at ~90-100us/frame - not precise, just long enough to observe

PUB Main
  cognew(@entry, 0)
  repeat                         ' main Spin cog has nothing else to do - the PASM cog does everything

DAT
                        org     0

entry                   rdlong  sysClk, #0              ' hub address 0 holds CLKFREQ, set by the boot process
                        mov     blinkDelay, sysClk
                        shr     blinkDelay, #2          ' sysClk/4 = 0.25s per half-blink (exact, since 4 = 2^2)
                        mov     pinIdx, #0

pinLoop                 mov     ledMask, #1
                        shl     ledMask, #LED_PIN
                        mov     dira, ledMask
                        mov     outa, #0

                        mov     blinkCnt, pinIdx
                        add     blinkCnt, #1            ' blink (pinIdx + 1) times - so pin 0 is 1 blink, not 0
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
                        mov     outa, #0

                        mov     repCnt, holdRepeats
sendLoop                mov     sendByte, #0            ' G = 0
                        call    #clockByte
                        mov     sendByte, #$FF          ' R = 255 (full red)
                        call    #clockByte
                        mov     sendByte, #0            ' B = 0
                        call    #clockByte

                        mov     time, cnt
                        add     time, resetCyc
                        waitcnt time, #0

                        djnz    repCnt, #sendLoop

                        add     pinIdx, #1
                        cmp     pinIdx, #16       wz
              if_z      mov     pinIdx, #0
                        jmp     #pinLoop

' --- clockByte: shifts sendByte out MSB-first on curMask, standard WS2812 single-wire timing ------------------
clockByte               mov     bitCnt, #8
:bitloop                mov     time, cnt
                        add     time, #40
                        or      outa, curMask           ' t=0: pin goes high

                        test    sendByte, #%1000_0000   wz

                        add     time, #T0H_CYC
                        waitcnt time, #0
              if_z      andn    outa, curMask           ' t=T0H: drop now if this was a '0' bit

                        add     time, #(T1H_CYC - T0H_CYC)
                        waitcnt time, #0
                        andn    outa, curMask           ' t=T1H: drop now regardless (no-op if already low)

                        add     time, #(BIT_PERIOD_CYC - T1H_CYC)
                        waitcnt time, #0

                        shl     sendByte, #1
                        djnz    bitCnt, #:bitloop
clockByte_ret           ret

sysClk                  res     1
blinkDelay              res     1
pinIdx                  res     1
ledMask                 res     1
blinkCnt                res     1
curMask                 res     1
repCnt                  res     1
sendByte                res     1
bitCnt                  res     1
time                    res     1

resetCyc                long    RESET_CYC
holdRepeats             long    HOLD_REPEATS

                        fit     496
