{{
  Main.spin - SanDevicesDDP firmware, E6804 build

  Top-level object: brings up the W5200 (vendored src/W5200_Driver.spin), opens a UDP socket on the DDP port,
  feeds received packets to DDP_Parser.spin, and runs PixelDriver_E6804.spin continuously off the same frame
  buffer. Pin numbers below are all taken directly from docs/pin_mapping_E6804.md - do not change them here,
  change the traced values there if they turn out to be wrong and re-copy.

  Network config (IP/gateway/subnet/MAC) is fixed at compile time for this first version - no EEPROM-backed
  Config.spin / web config page yet (that's plan Step 6). Per-port pixel counts are likewise compile-time
  constants below until then; edit PORT1_PIXELS..PORT4_PIXELS to match your actual strings before flashing.

  NOT YET COMPILED OR TESTED - no Propeller toolchain available in this environment. This is a first-pass
  integration written directly against the traced E6804 pin table and the vendored W5200 driver's real API
  (see vendor/W5200_Driver/PROVENANCE.md) - compile with Propeller Tool and bring up cog-by-cog per the plan's
  verification section before trusting it on a real board.
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
  long  pinTable[NUM_PORTS]              ' pixel output pin per port, same order as portTable

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
  pixels.Start(@framebuffer, @portTable, @pinTable)

  greenState := 0

  repeat
    bytesRead := w5200.rxUDP(0, @rxBuf)
    if bytesRead > 8
      if ddp.ProcessPacket(@rxBuf + 8, bytesRead - 8)
        greenState := !greenState
        outa[PIN_LED_GREEN] := greenState                     ' toggles on each accepted DDP frame - activity heartbeat
