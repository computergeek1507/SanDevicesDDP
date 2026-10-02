{{
  Pixel_Red_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Bypasses W5200/DDP entirely: hardcodes 10 red
  pixels into a frame buffer once at startup, then just runs PixelDriver_E6804.spin forever off that static buffer.

  Purpose: isolate whether PixelDriver_E6804.spin's WS2812 PASM driver itself works at all, separate from anything
  in Main.spin's DDP-to-framebuffer wiring. If J1 lights up red here, the pixel driver is fine and the real bug is
  somewhere in how Main.spin feeds it DDP data (or a race/timing issue between the two). If J1 stays dark or wrong
  here too, the bug is in PixelDriver_E6804.spin's PASM itself.

  Only port J1 is populated (10 pixels) - J2/J3/J4 are left at zero length (disabled).
}}

CON
  _clkmode  = xtal1 + pll16x
  _xinfreq  = 5_000_000                  ' 5MHz crystal, matches E6804

  NUM_PIXELS = 10                        ' how many pixels on J1 to light up

OBJ
  pixels : "../src/PixelDriver_E6804"

VAR
  long  portTable[8]
  long  pinTable[4]
  byte  framebuffer[NUM_PIXELS * 3]

PUB Main | i
  pinTable[0] := 0                       ' J1 data pin, per docs/pin_mapping_E6804.md
  pinTable[1] := 4                       ' J2
  pinTable[2] := 8                       ' J3
  pinTable[3] := 12                      ' J4

  portTable[0] := 0                      ' J1 start channel
  portTable[1] := NUM_PIXELS * 3         ' J1 length - the only port with real data
  portTable[2] := 0                      ' J2 start (unused)
  portTable[3] := 0                      ' J2 length = 0 -> disabled
  portTable[4] := 0                      ' J3 start (unused)
  portTable[5] := 0                      ' J3 length = 0 -> disabled
  portTable[6] := 0                      ' J4 start (unused)
  portTable[7] := 0                      ' J4 length = 0 -> disabled

  repeat i from 0 to NUM_PIXELS - 1
    framebuffer[i * 3 + 0] := 255        ' R
    framebuffer[i * 3 + 1] := 0          ' G
    framebuffer[i * 3 + 2] := 0          ' B

  pixels.Start(@framebuffer, @portTable, @pinTable)

  repeat                                 ' nothing else to do - the pixel driver's own cog handles output
