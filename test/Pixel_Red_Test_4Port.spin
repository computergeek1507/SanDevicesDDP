{{
  Pixel_Red_Test_4Port.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Same idea as Pixel_Red_Test.spin, but matches
  Main.spin's EXACT port table shape: all 4 ports active simultaneously, 50 pixels each (not just J1 active with
  the others disabled at length 0, which is what Pixel_Red_Test.spin actually tested).

  Purpose: Main.spin (real DDP packet, green LED confirms acceptance) produces no visible pixel change, while
  Pixel_Red_Test.spin (hardcoded data, only J1 active, others disabled) correctly showed red. Those two tests
  exercise genuinely different code paths in PixelDriver_E6804.spin's PASM - rdbyte/activemask/zeromask logic for
  ports 2-4 never actually executed in Pixel_Red_Test.spin because their length was 0. This test hardcodes red into
  ALL 4 ports' regions, bypassing DDP/W5200 entirely, to isolate whether the "all 4 ports genuinely active" code
  path itself has a bug - independent of anything DDP-related.
}}

CON
  _clkmode  = xtal1 + pll16x
  _xinfreq  = 5_000_000

  NUM_PORTS    = 4
  PORT_PIXELS  = 50                      ' matches Main.spin's PORT1_PIXELS..PORT4_PIXELS

OBJ
  pixels : "../src/PixelDriver_E6804"

VAR
  long  portTable[8]
  long  pinTable[4]
  byte  framebuffer[PORT_PIXELS * 4 * 3]

PUB Main | i
  pinTable[0] := 0                       ' J1
  pinTable[1] := 4                       ' J2
  pinTable[2] := 8                       ' J3
  pinTable[3] := 12                      ' J4

  portTable[0] := 0                                          ' J1 start
  portTable[1] := PORT_PIXELS * 3                             ' J1 length
  portTable[2] := portTable[0] + portTable[1]                 ' J2 start
  portTable[3] := PORT_PIXELS * 3                             ' J2 length
  portTable[4] := portTable[2] + portTable[3]                 ' J3 start
  portTable[5] := PORT_PIXELS * 3                             ' J3 length
  portTable[6] := portTable[4] + portTable[5]                 ' J4 start
  portTable[7] := PORT_PIXELS * 3                             ' J4 length

  repeat i from 0 to (PORT_PIXELS * 4) - 1
    framebuffer[i * 3 + 0] := 255        ' R
    framebuffer[i * 3 + 1] := 0          ' G
    framebuffer[i * 3 + 2] := 0          ' B

  pixels.Start(@framebuffer, @portTable, @pinTable)

  repeat
