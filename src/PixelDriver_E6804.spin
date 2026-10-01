{{
  PixelDriver_E6804.spin

  4-port APA102/SK9822-style clocked pixel output driver for the SanDevices E6804, using the traced pin mapping in
  docs/pin_mapping_E6804.md: data J1=P0/J2=P4/J3=P8/J4=P12, clock J1=P21/J2=P22/J3=P20/J4=P19.

  Rewritten from an earlier WS2811 single-wire version once tracing found a dedicated clock pin per port - these
  boards drive 2-wire clocked pixel chips (APA102/SK9822), not single-wire WS2811/WS2812. Clocked protocols have no
  tight pulse-width timing requirement (the receiver samples on clock edges, not pulse duration), so unlike the old
  WS2811 driver this one does NOT need all 4 ports bit-banged in parallel lockstep - it just sends them one after
  another in a simple loop, which is both simpler and still fast enough (4 ports x ~50 pixels x 4 bytes/pixel x 8
  bits, at the clock rate below, comfortably clears 20-40fps).

  Per-port frame format (APA102/SK9822):
    - start frame:  4 bytes of 0x00
    - per pixel:    1 byte 0xFF (brightness field forced to max - 0b111 + 5-bit brightness all set; DDP already
                    sends full-scale color values, so no separate dimming is applied here), then the pixel's 3 raw
                    bytes from the frame buffer, UNCHANGED ORDER - same "pass channel order through as received"
                    approach as the rest of this firmware. If colors come out swapped, fix it at the sender (e.g.
                    xLights' per-output color-order setting), not here.
    - end frame:    enough extra clock pulses (data held low) to latch the last pixel through the chain -
                    ceil(pixelCount/16) bytes of 0x00, per Start()'s endFrameBytesPtr argument (computed in
                    Main.spin with real division, since PASM on the P1 has no divide instruction)

  NOT YET COMPILED OR TESTED ON HARDWARE - no Propeller toolchain available in this environment. Verify clock/data
  relationship and end-frame length against your actual APA102/SK9822 strings (a logic analyzer helps) before
  trusting this on real hardware.
}}

CON
  NUM_PORTS         = 4

  ' Clock pacing - not a protocol requirement (APA102/SK9822 have no minimum clock period, only a maximum), just a
  ' conservative rate for signal integrity over long cable runs through the board's 74HCT541 buffers. ~1MHz.
  CLK_HALF_CYC      = 40          ' 0.5us high, 0.5us low -> 1us period -> ~1MHz clock

VAR
  long  cog
  long  paramBlock[5]

PUB Start(fbPtr, portTablePtr, dataPinsPtr, clockPinsPtr, endFrameBytesPtr) : ok
'' fbPtr             - hub address of the shared pixel frame buffer (same one DDP_Parser.spin writes into)
'' portTablePtr      - hub address of NUM_PORTS x (long startChannel, long numBytes) pairs - same table/format
''                     DDP_Parser.spin uses
'' dataPinsPtr       - hub address of NUM_PORTS longs: data pin per port (J1..J4 -> P0,P4,P8,P12)
'' clockPinsPtr      - hub address of NUM_PORTS longs: clock pin per port (J1..J4 -> P21,P22,P20,P19)
'' endFrameBytesPtr  - hub address of NUM_PORTS longs: precomputed ceil(pixelCount/16) per port - computed in
''                     Spin (Main.spin) since PASM has no divide instruction
  Stop
  paramBlock[0] := fbPtr
  paramBlock[1] := portTablePtr
  paramBlock[2] := dataPinsPtr
  paramBlock[3] := clockPinsPtr
  paramBlock[4] := endFrameBytesPtr
  cog := cognew(@entry, @paramBlock) + 1
  ok := cog <> 0

PUB Stop
  if cog
    cogstop(cog - 1)
    cog := 0

DAT
                        org     0

entry                   mov     t1, par
                        rdlong  fbAddr, t1
                        add     t1, #4
                        rdlong  tblAddr, t1
                        add     t1, #4
                        rdlong  dataAddr, t1
                        add     t1, #4
                        rdlong  clkAddr, t1
                        add     t1, #4
                        rdlong  endAddr, t1

                        rdlong  dpin0, dataAddr
                        mov     t2, dataAddr
                        add     t2, #4
                        rdlong  dpin1, t2
                        add     t2, #4
                        rdlong  dpin2, t2
                        add     t2, #4
                        rdlong  dpin3, t2

                        rdlong  cpin0, clkAddr
                        mov     t2, clkAddr
                        add     t2, #4
                        rdlong  cpin1, t2
                        add     t2, #4
                        rdlong  cpin2, t2
                        add     t2, #4
                        rdlong  cpin3, t2

                        mov     dmask0, #1
                        shl     dmask0, dpin0
                        mov     dmask1, #1
                        shl     dmask1, dpin1
                        mov     dmask2, #1
                        shl     dmask2, dpin2
                        mov     dmask3, #1
                        shl     dmask3, dpin3

                        mov     cmask0, #1
                        shl     cmask0, cpin0
                        mov     cmask1, #1
                        shl     cmask1, cpin1
                        mov     cmask2, #1
                        shl     cmask2, cpin2
                        mov     cmask3, #1
                        shl     cmask3, cpin3

                        mov     allmask, dmask0
                        or      allmask, dmask1
                        or      allmask, dmask2
                        or      allmask, dmask3
                        or      allmask, cmask0
                        or      allmask, cmask1
                        or      allmask, cmask2
                        or      allmask, cmask3

                        mov     dira, allmask
                        mov     outa, #0

                        rdlong  start0, tblAddr
                        mov     t2, tblAddr
                        add     t2, #4
                        rdlong  len0, t2
                        add     t2, #4
                        rdlong  start1, t2
                        add     t2, #4
                        rdlong  len1, t2
                        add     t2, #4
                        rdlong  start2, t2
                        add     t2, #4
                        rdlong  len2, t2
                        add     t2, #4
                        rdlong  start3, t2
                        add     t2, #4
                        rdlong  len3, t2

                        rdlong  endf0, endAddr
                        mov     t2, endAddr
                        add     t2, #4
                        rdlong  endf1, t2
                        add     t2, #4
                        rdlong  endf2, t2
                        add     t2, #4
                        rdlong  endf3, t2

refresh                 mov     curData, dmask0
                        mov     curClk, cmask0
                        mov     curPtr, fbAddr
                        add     curPtr, start0
                        mov     curLen, len0
                        mov     curEnd, endf0
                        call    #sendPort

                        mov     curData, dmask1
                        mov     curClk, cmask1
                        mov     curPtr, fbAddr
                        add     curPtr, start1
                        mov     curLen, len1
                        mov     curEnd, endf1
                        call    #sendPort

                        mov     curData, dmask2
                        mov     curClk, cmask2
                        mov     curPtr, fbAddr
                        add     curPtr, start2
                        mov     curLen, len2
                        mov     curEnd, endf2
                        call    #sendPort

                        mov     curData, dmask3
                        mov     curClk, cmask3
                        mov     curPtr, fbAddr
                        add     curPtr, start3
                        mov     curLen, len3
                        mov     curEnd, endf3
                        call    #sendPort

                        jmp     #refresh

' --- sendPort: sends one port's full APA102/SK9822 frame -------------------------------------------------------
' in:  curData, curClk (pin masks), curPtr (frame buffer address for this port), curLen (bytes = pixelCount*3),
'      curEnd (precomputed end-frame byte count)
sendPort                mov     sendCount, #4           ' start frame: 4 bytes of 0x00
                        mov     sendByte, #0
:startloop              call    #clockByte
                        djnz    sendCount, #:startloop

                        mov     remaining, curLen
:pixloop                cmp     remaining, #0     wz
              if_z      jmp     #:pixdone
                        mov     sendByte, #$FF          ' brightness byte, forced to max
                        call    #clockByte
                        rdbyte  sendByte, curPtr
                        call    #clockByte
                        add     curPtr, #1
                        rdbyte  sendByte, curPtr
                        call    #clockByte
                        add     curPtr, #1
                        rdbyte  sendByte, curPtr
                        call    #clockByte
                        add     curPtr, #1
                        sub     remaining, #3
                        jmp     #:pixloop
:pixdone

                        mov     sendCount, curEnd       ' end frame: curEnd bytes of 0x00
                        mov     sendByte, #0
:endloop                cmp     sendCount, #0     wz
              if_z      jmp     #:enddone
                        call    #clockByte
                        sub     sendCount, #1
                        jmp     #:endloop
:enddone
sendPort_ret            ret

' --- clockByte: shifts sendByte out MSB-first on curData/curClk ------------------------------------------------
clockByte               mov     bitCnt, #8
:bitloop                test    sendByte, #%1000_0000   wz
              if_nz     or      outa, curData
              if_z      andn    outa, curData

                        mov     ctime, cnt
                        add     ctime, #CLK_HALF_CYC
                        waitcnt ctime, #0
                        or      outa, curClk            ' clock high - receiver samples data now

                        add     ctime, #CLK_HALF_CYC
                        waitcnt ctime, #0
                        andn    outa, curClk            ' clock low

                        shl     sendByte, #1
                        djnz    bitCnt, #:bitloop
clockByte_ret           ret

' parameters (set once at startup)
fbAddr                  res     1
tblAddr                 res     1
dataAddr                res     1
clkAddr                 res     1
endAddr                 res     1
dpin0                   res     1
dpin1                   res     1
dpin2                   res     1
dpin3                   res     1
cpin0                   res     1
cpin1                   res     1
cpin2                   res     1
cpin3                   res     1
dmask0                  res     1
dmask1                  res     1
dmask2                  res     1
dmask3                  res     1
cmask0                  res     1
cmask1                  res     1
cmask2                  res     1
cmask3                  res     1
allmask                 res     1
start0                  res     1
start1                  res     1
start2                  res     1
start3                  res     1
len0                    res     1
len1                    res     1
len2                    res     1
len3                    res     1
endf0                   res     1
endf1                   res     1
endf2                   res     1
endf3                   res     1

' per-sendPort working state
curData                 res     1
curClk                  res     1
curPtr                  res     1
curLen                  res     1
curEnd                  res     1
sendCount               res     1
sendByte                res     1
remaining               res     1
bitCnt                  res     1
ctime                   res     1
t1                      res     1
t2                      res     1

                        fit     496
