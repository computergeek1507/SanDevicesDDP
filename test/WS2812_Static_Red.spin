{{
  WS2812_Static_Red.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. The absolute minimal possible WS2812 test: drives
  ONLY P0, forever, with a single hardcoded red pixel. No pin cycling, no LED blink indicator, no dira switching
  between phases - just the bare clockByte bit-banging loop sending the same 3 bytes over and over.

  Purpose: WS2812_Pin_Scanner.spin (pin cycling + LED blink indicator) worked once (lit red on P0) then started
  showing stuck white on every later run, with no code changes, same board/pixel power-cycled, same pixel swapped.
  This strips out everything except the core bit-banging routine itself, to get the cleanest possible test of
  whether that routine is actually correct, with zero other moving parts (no dira reassignment between an LED
  phase and a pixel phase, no loop-driven pin selection).
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  DATA_PIN       = 0             ' P0, per docs/pin_mapping_E6804.md

  BIT_PERIOD_CYC = 100
  T0H_CYC        = 32
  T1H_CYC        = 64
  RESET_CYC      = 4800

PUB Main
  cognew(@entry, 0)
  repeat

DAT
                        org     0

entry                   mov     curMask, #1
                        shl     curMask, #DATA_PIN
                        mov     dira, curMask
                        mov     outa, #0

sendLoop                mov     sendByte, #0            ' G = 0
                        call    #clockByte
                        mov     sendByte, #$FF          ' R = 255
                        call    #clockByte
                        mov     sendByte, #0            ' B = 0
                        call    #clockByte

                        mov     time, cnt
                        add     time, resetCyc
                        waitcnt time, #0

                        jmp     #sendLoop

clockByte               mov     bitCnt, #8
:bitloop                mov     time, cnt
                        add     time, #40
                        or      outa, curMask

                        test    sendByte, #%1000_0000   wz

                        add     time, #T0H_CYC
                        waitcnt time, #0
              if_z      andn    outa, curMask

                        add     time, #(T1H_CYC - T0H_CYC)
                        waitcnt time, #0
                        andn    outa, curMask

                        add     time, #(BIT_PERIOD_CYC - T1H_CYC)
                        waitcnt time, #0

                        shl     sendByte, #1
                        djnz    bitCnt, #:bitloop
clockByte_ret           ret

curMask                 res     1
sendByte                res     1
bitCnt                  res     1
time                    res     1

resetCyc                long    RESET_CYC

                        fit     496
