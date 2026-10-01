{{
  Main.spin - SanDevicesDDP firmware, E6804 build

  Top-level object: brings up the W5200 (vendored src/W5200_Driver.spin), opens a UDP socket on the DDP port,
  feeds received packets to DDP_Parser.spin, and runs PixelDriver_E6804.spin continuously off the same frame
  buffer. Pin numbers below are all taken directly from docs/pin_mapping_E6804.md - do not change them here,
  change the traced values there if they turn out to be wrong and re-copy.

  Network config (IP/gateway/subnet/MAC) is fixed at compile time for this first version - no EEPROM-backed
  Config.spin / web config page yet (that's plan Step 6). Per-port pixel counts are likewise compile-time
  constants below until then; edit PORT1_PIXELS..PORT4_PIXELS to match your actual strings before flashing.

  Toolchain in actual use turned out to be FlexProp/flexspin (cross-platform), not the original Windows-only
  Propeller Tool - make sure it's targeting P1 (Propeller 1 / P8X32A), not its P2 default.

  Status as of the last hardware test: compiles clean, loads to RAM fine, red status LED confirmed lighting up
  (proves execution reaches past the W5200 setup calls without hanging). Network bring-up (ping test) and the
  pixel output stage are still being verified - see docs/NOTES.md for the full history. Pixel outputs drive
  APA102/SK9822-style 2-wire (clock+data) strings, not single-wire WS2811 - confirmed by tracing a dedicated clock
  pin per port (see docs/pin_mapping_E6804.md).
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000                   ' 5MHz crystal, matches E6804 (docs/NOTES.md)

  NUM_PORTS      = 4

  ' --- pins, from docs/pin_mapping_E6804.md ---
  PIN_PIX_J1     = 0
  PIN_PIX_J2     = 4
  PIN_PIX_J3     = 8
  PIN_PIX_J4     = 12

  ' Clock pins for the APA102/SK9822-style 2-wire pixel outputs - see docs/pin_mapping_E6804.md
  PIN_CLK_J1     = 21
  PIN_CLK_J2     = 22
  PIN_CLK_J3     = 20
  PIN_CLK_J4     = 19

  PIN_LED_GREEN  = 16
  PIN_LED_RED    = 17

  PIN_W5200_MISO = 23
  PIN_W5200_MOSI = 24
  PIN_W5200_RST  = 25
  PIN_W5200_CS   = 26
  PIN_W5200_SCLK = 27
  ' W5200 INT is not wired on this board - the vendored driver doesn't use it anyway (polls status via SPI)

  ' --- network config (fixed for now - see Config.spin/HTTPServer.spin, plan Step 6, once built) ---
  ' Default IP matches SanDevices' own stock default (192.168.1.206) so this drops into the same LAN setup
  ' the stock firmware expected.
  IP0 = 192
  IP1 = 168
  IP2 = 1
  IP3 = 206

  GW0 = 192
  GW1 = 168
  GW2 = 1
  GW3 = 1

  SUB0 = 255
  SUB1 = 255
  SUB2 = 255
  SUB3 = 0

  ' --- per-port pixel counts (fixed for now) - edit to match your actual strings ---
  PORT1_PIXELS = 50
  PORT2_PIXELS = 50
  PORT3_PIXELS = 50
  PORT4_PIXELS = 50

  RX_BUF_SIZE  = 1500                    ' bigger than any realistic single DDP+pseudo-header packet

OBJ
  w5200  : "W5200_Driver"
  ddp    : "DDP_Parser"
  pixels : "PixelDriver_E6804"

VAR
  byte  mac[6]
  byte  gateway[4]
  byte  subnet[4]
  byte  myip[4]

  long  portTable[NUM_PORTS * 2]         ' (startChannel, numBytes) pairs, shared by DDP_Parser and PixelDriver
  long  pinTable[NUM_PORTS]              ' pixel data pin per port, same order as portTable
  long  clockPinTable[NUM_PORTS]         ' pixel clock pin per port (APA102/SK9822 2-wire outputs)
  long  endFrameBytes[NUM_PORTS]         ' precomputed ceil(pixelCount/16) per port - APA102/SK9822 end-frame length

  byte  framebuffer[(PORT1_PIXELS + PORT2_PIXELS + PORT3_PIXELS + PORT4_PIXELS) * 3]
  byte  rxBuf[RX_BUF_SIZE]

PUB Main | bytesRead, greenState

  ' Locally-administered MAC (bit 1 of first octet set, per IEEE convention for non-globally-unique addresses).
  ' Change the last 3 octets if running more than one of these on the same LAN.
  mac[0] := $02
  mac[1] := $00
  mac[2] := $00
  mac[3] := $00
  mac[4] := $00
  mac[5] := $01

  gateway[0] := GW0
  gateway[1] := GW1
  gateway[2] := GW2
  gateway[3] := GW3

  subnet[0] := SUB0
  subnet[1] := SUB1
  subnet[2] := SUB2
  subnet[3] := SUB3

  myip[0] := IP0
  myip[1] := IP1
  myip[2] := IP2
  myip[3] := IP3

  pinTable[0] := PIN_PIX_J1
  pinTable[1] := PIN_PIX_J2
  pinTable[2] := PIN_PIX_J3
  pinTable[3] := PIN_PIX_J4

  clockPinTable[0] := PIN_CLK_J1
  clockPinTable[1] := PIN_CLK_J2
  clockPinTable[2] := PIN_CLK_J3
  clockPinTable[3] := PIN_CLK_J4

  ' APA102/SK9822 end-frame length: ceil(pixelCount/16) bytes of extra clocking to latch the last pixel through -
  ' computed here with real division since PASM on the P1 has no divide instruction.
  endFrameBytes[0] := (PORT1_PIXELS + 15) / 16
  endFrameBytes[1] := (PORT2_PIXELS + 15) / 16
  endFrameBytes[2] := (PORT3_PIXELS + 15) / 16
  endFrameBytes[3] := (PORT4_PIXELS + 15) / 16

  portTable[0] := 0                                          ' J1 start channel (byte offset)
  portTable[1] := PORT1_PIXELS * 3                            ' J1 byte length
  portTable[2] := portTable[0] + portTable[1]                 ' J2 start channel
  portTable[3] := PORT2_PIXELS * 3
  portTable[4] := portTable[2] + portTable[3]                 ' J3 start channel
  portTable[5] := PORT3_PIXELS * 3
  portTable[6] := portTable[4] + portTable[5]                 ' J4 start channel
  portTable[7] := PORT4_PIXELS * 3

  dira[PIN_LED_RED]~~
  dira[PIN_LED_GREEN]~~
  outa[PIN_LED_RED]~~                                         ' solid red = powered/running, matches stock behavior

  w5200.start(PIN_W5200_CS, PIN_W5200_SCLK, PIN_W5200_MOSI, PIN_W5200_MISO, PIN_W5200_RST)
  w5200.InitAddresses(true, @mac, @gateway, @subnet, @myip)
  w5200.SocketOpen(0, w5200#_UDPPROTO, ddp#DDP_PORT, 0, 0)

  ddp.Start(@framebuffer, @portTable, NUM_PORTS)
  pixels.Start(@framebuffer, @portTable, @pinTable, @clockPinTable, @endFrameBytes)

  greenState := 0

  repeat
    bytesRead := w5200.rxUDP(0, @rxBuf)
    if bytesRead > 8
      if ddp.ProcessPacket(@rxBuf + 8, bytesRead - 8)
        greenState := !greenState
        outa[PIN_LED_GREEN] := greenState                     ' toggles on each accepted DDP frame - activity heartbeat
