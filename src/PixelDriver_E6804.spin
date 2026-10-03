{{
  PixelDriver_E6804.spin

  4-port WS2812/WS2811 single-wire parallel bit-bang pixel output driver for the SanDevices E6804, using the
  traced data pins in docs/pin_mapping_E6804.md: J1=P0, J2=P4, J3=P8, J4=P12.

  Reverted back to single-wire from a brief APA102/SK9822 2-wire (clock+data) detour: the board does have real,
  separately-traced clock pins per port (J1=P21, J2=P22, J3=P20, J4=P19 - see docs/pin_mapping_E6804.md), but the
  actual pixel strip on hand for bring-up testing turned out to be WS2812 (single-wire, no clock input at all), so
  this driver needs to match what's actually being tested right now. The user wants to support BOTH eventually -
  tracked as follow-up work (see docs/NOTES.md and README.md), most likely as a second, separate PASM cog dedicated
  to APA102/SK9822-style ports once some are available to test against, rather than mixing both protocols in one
  cog (WS2812's single-wire timing is too strict to interleave cleanly with APA102's more relaxed clocked timing).

  Runs continuously in its own cog, reading directly from the same hub-RAM frame buffer and port table that
  DDP_Parser.spin writes into (same (startChannel, numBytes) pair format, same buffer address).

  Timing targets WS2812/WS2812B (800kHz-class), matching the actual test strip - NOT the older ~400kHz WS2811
  timing used in classic 12V "bullet"/C9-style pixel strings. If strings on other ports turn out to be WS2811-class
  instead, change T0H_CYC/T1H_CYC/BIT_PERIOD_CYC below (values in comments).

  Uses the standard Propeller multi-pin parallel bit-bang technique: raise all active pins high together at the
  start of each bit time, drop "0"-bit pins low at T0H, drop all remaining ("1"-bit) pins low at T1H, then wait out
  the rest of the bit period - so all 4 output streams share one timing reference and stay in lockstep regardless
  of their individual byte content.

  The underlying bit-timing technique (and a real timing bug in it - see docs/NOTES.md) has been confirmed against
  real hardware via test/WS2812_Static_Red.spin - a single-pin version of the exact same clockByte approach used
  here, which now correctly lights a WS2812 pixel red. This 4-port version has the same bug fixes applied but
  hasn't itself been re-tested on hardware since - verify with test/Pixel_Red_Test.spin before fully trusting it.

  Byte order: this driver passes the 3 bytes per pixel straight from the frame buffer onto the wire, unmodified -
  no reordering. The test pixel used for bring-up turned out to want plain R,G,B order (not the G,R,B order many
  WS2812 chips use), which happens to match DDP's conventional RGB8 sender order already, so no reordering was
  needed here. If a future pixel type wants a different order, handle it at the sender (e.g. xLights' per-output
  color-order setting) rather than adding reordering logic here, to keep this driver protocol-agnostic about it.
}}

CON
  NUM_PORTS       = 4

  ' WS2812/WS2812B (800kHz-class) bit timing at 80MHz core clock (12.5ns/cycle). For classic WS2811 (~400kHz)
  ' strings instead, use BIT_PERIOD_CYC=200, T0H_CYC=40, T1H_CYC=96.
  BIT_PERIOD_CYC  = 100         ' 1.25us total bit period
  T0H_CYC         = 32          ' 0.4us - high time for a '0' bit
  T1H_CYC         = 64          ' 0.8us - high time for a '1' bit
  RESET_CYC       = 4800        ' 60us low gap between frames (latch/reset)

VAR
  long  cog
  long  paramBlock[3]

PUB Start(fbPtr, portTablePtr, pinsPtr) : ok
'' fbPtr        - hub address of the shared pixel frame buffer (same one DDP_Parser.spin writes into)
'' portTablePtr - hub address of NUM_PORTS x (long startChannel, long numBytes) pairs - same table/format
''                DDP_Parser.spin uses, so both objects can be started with the same pointer
'' pinsPtr      - hub address of NUM_PORTS longs: the Propeller pin number for each port, in the same order
''                as the port table (J1, J2, J3, J4 -> P0, P4, P8, P12 per docs/pin_mapping_E6804.md)
  Stop
  paramBlock[0] := fbPtr
  paramBlock[1] := portTablePtr
  paramBlock[2] := pinsPtr
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
                        rdlong  pinAddr, t1

                        rdlong  pin0, pinAddr
                        mov     t2, pinAddr
                        add     t2, #4
                        rdlong  pin1, t2
                        add     t2, #4
                        rdlong  pin2, t2
                        add     t2, #4
                        rdlong  pin3, t2

                        mov     mask0, #1
                        shl     mask0, pin0
                        mov     mask1, #1
                        shl     mask1, pin1
                        mov     mask2, #1
                        shl     mask2, pin2
                        mov     mask3, #1
                        shl     mask3, pin3

                        mov     allmask, mask0
                        or      allmask, mask1
                        or      allmask, mask2
                        or      allmask, mask3

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

refresh                 mov     byteIdx, #0
                        mov     ptr0, fbAddr
                        add     ptr0, start0
                        mov     ptr1, fbAddr
                        add     ptr1, start1
                        mov     ptr2, fbAddr
                        add     ptr2, start2
                        mov     ptr3, fbAddr
                        add     ptr3, start3

                        mov     maxlen, len0
                        max     maxlen, len1
                        max     maxlen, len2
                        max     maxlen, len3

byteloop                cmp     byteIdx, len0     wc
              if_b      rdbyte  b0, ptr0
              if_nc     mov     b0, #0
                        cmp     byteIdx, len1     wc
              if_b      rdbyte  b1, ptr1
              if_nc     mov     b1, #0
                        cmp     byteIdx, len2     wc
              if_b      rdbyte  b2, ptr2
              if_nc     mov     b2, #0
                        cmp     byteIdx, len3     wc
              if_b      rdbyte  b3, ptr3
              if_nc     mov     b3, #0

                        mov     bitIdx, #8

bitloop                 mov     activemask, #0
                        cmp     byteIdx, len0     wc
              if_b      or      activemask, mask0
                        cmp     byteIdx, len1     wc
              if_b      or      activemask, mask1
                        cmp     byteIdx, len2     wc
              if_b      or      activemask, mask2
                        cmp     byteIdx, len3     wc
              if_b      or      activemask, mask3

                        mov     zeromask, #0
                        test    b0, #%1000_0000   wz
              if_z      or      zeromask, mask0
                        test    b1, #%1000_0000   wz
              if_z      or      zeromask, mask1
                        test    b2, #%1000_0000   wz
              if_z      or      zeromask, mask2
                        test    b3, #%1000_0000   wz
              if_z      or      zeromask, mask3

                        ' Timing reference is captured HERE, right before actually going high - not at the top of
                        ' this loop - because the port-checking work above (8 conditional cmp/test instructions)
                        ' takes ~60+ cycles, which blew past the T0H deadline if "time" was set before doing it
                        ' (a real bug found during hardware bring-up - see docs/NOTES.md). A second, separate bug
                        ' was fixed here too: there used to be a "+40 cycle lead-in" added to "time" before this
                        ' point, but since nothing ever actually WAITED for those 40 cycles (the pin goes high on
                        ' the very next instruction), every deadline below was being measured 40 cycles later than
                        ' the pin's real high transition - silently stretching every pulse (0-bit and 1-bit alike)
                        ' by ~500ns, well outside what a WS2812 can reliably tell apart. "time" must be captured
                        ' immediately before the instruction that actually changes the pin, with nothing but a
                        ' single OR in between - not before a delay that's never waited for.
                        mov     time, cnt
                        or      outa, activemask       ' t=0: all active pins go high together

                        add     time, #T0H_CYC
                        waitcnt time, #0
                        andn    outa, zeromask         ' t=T0H: '0'-bit pins drop low

                        add     time, #(T1H_CYC - T0H_CYC)
                        waitcnt time, #0
                        andn    outa, activemask       ' t=T1H: remaining ('1'-bit) pins drop low

                        add     time, #(BIT_PERIOD_CYC - T1H_CYC)
                        waitcnt time, #0                ' t=BIT_PERIOD: next bit

                        shl     b0, #1
                        shl     b1, #1
                        shl     b2, #1
                        shl     b3, #1

                        djnz    bitIdx, #bitloop

                        add     ptr0, #1
                        add     ptr1, #1
                        add     ptr2, #1
                        add     ptr3, #1
                        add     byteIdx, #1
                        cmp     byteIdx, maxlen   wc
              if_b      jmp     #byteloop

                        mov     time, cnt
                        add     time, resetCyc          ' RESET_CYC (4800) is too big for a 9-bit PASM immediate,
                        waitcnt time, #0                ' so it's stashed in a long and referenced directly below

                        jmp     #refresh

' parameters (set once at startup) - named differently from Start()'s fbPtr/portTablePtr/pinsPtr params above:
' Spin1 requires every symbol in a file (CON/VAR/params/locals AND DAT labels/res vars) to be globally unique
' within that file, so these PASM-side copies can't reuse the Spin method's parameter names.
fbAddr                  res     1
tblAddr                 res     1
pinAddr                 res     1
pin0                    res     1
pin1                    res     1
pin2                    res     1
pin3                    res     1
mask0                   res     1
mask1                   res     1
mask2                   res     1
mask3                   res     1
allmask                 res     1
start0                  res     1
start1                  res     1
start2                  res     1
start3                  res     1
len0                    res     1
len1                    res     1
len2                    res     1
len3                    res     1

' per-refresh working state
ptr0                    res     1
ptr1                    res     1
ptr2                    res     1
ptr3                    res     1
byteIdx                 res     1
maxlen                  res     1
bitIdx                  res     1
b0                      res     1
b1                      res     1
b2                      res     1
b3                      res     1
time                    res     1
activemask              res     1
zeromask                res     1
t1                      res     1
t2                      res     1

resetCyc                long    RESET_CYC               ' initialized value, not res - too big for a #immediate

                        fit     496
