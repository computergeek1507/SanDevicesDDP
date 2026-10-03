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

  Status as of the last hardware test: compiles clean, loads to RAM fine, W5200 link/ping/DDP receive path all
  confirmed working on real hardware (green activity LED toggles on a received DDP packet - see
  tools/send_test_ddp.py). Pixel output is back to single-wire WS2812/WS2811 for now (PixelDriver_E6804.spin) -
  the board does have real per-port clock pins traced for APA102/SK9822 2-wire output too (see
  docs/pin_mapping_E6804.md), but the test strip on hand turned out to be WS2812, so that's what's wired up first.
  APA102 dual-mode support is tracked as follow-up work once there's real APA102/SK9822 hardware to test against.

  Network settings, the DDP port, and per-port pixel counts are now EEPROM-backed (Config.spin) instead of fixed
  CON constants - see docs/NOTES.md for the EEPROM layout. A small HTTP server (HTTPServer.spin, polled from the
  same loop as DDP - no second cog) serves a config page on port 80; saving it writes the new config to EEPROM and
  REBOOTs so everything (W5200, pixel driver, port table) restarts cleanly with the new values, rather than trying
  to live-reinitialize an already-running system.
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

  ' Clock pins for the APA102/SK9822-style 2-wire pixel outputs - traced and real (see docs/pin_mapping_E6804.md),
  ' but not currently used - PixelDriver_E6804.spin is single-wire WS2812/WS2811 for now. Reserved here for the
  ' planned APA102 dual-mode follow-up.
  PIN_CLK_J1     = 21
  PIN_CLK_J2     = 22
  PIN_CLK_J3     = 20
  PIN_CLK_J4     = 19

  PIN_LED_GREEN  = 16
  PIN_LED_RED    = 17

  ' Tried swapping MOSI/MISO as an experiment (no link LED either way) - reverted to the original traced values.
  ' See docs/NOTES.md for the full W5200 bring-up troubleshooting history.
  PIN_W5200_MISO = 23
  PIN_W5200_MOSI = 24
  PIN_W5200_RST  = 25
  PIN_W5200_CS   = 26
  PIN_W5200_SCLK = 27
  ' W5200 INT is not wired on this board - the vendored driver doesn't use it anyway (polls status via SPI)

  ' Boot EEPROM I2C pins - the Propeller's own default boot pins, confirmed unchanged on this board
  ' (docs/pin_mapping_E6804.md). Shared with Config.spin's persistent settings block above offset $8000 -
  ' see docs/NOTES.md for why that's safe (above the full 32KB boot image, same 64KB I2C block).
  PIN_I2C_SCL    = 28
  PIN_I2C_SDA    = 29

  HTTP_PORT      = 80                    ' config web page - see HTTPServer.spin
  HTTP_BUF_SIZE  = 1024

  ' Network settings, the DDP port, and per-port pixel counts used to be fixed constants here - they're now
  ' EEPROM-backed via Config.spin (which falls back to the same values this block used to have if the EEPROM
  ' has no valid saved config yet - see Config.LoadDefaults). Edit Config.spin's LoadDefaults to change the
  ' out-of-the-box defaults; edit the running config via the web page (HTTPServer.spin) to change a live board.

  RX_BUF_SIZE  = 1500                    ' bigger than any realistic single DDP+pseudo-header packet

  ' HTTP request-handling states, see PollHTTP
  ST_LISTEN        = 0
  ST_AWAIT_REQUEST = 1
  ST_SERVE         = 2

OBJ
  w5200      : "W5200_Driver"
  ddp        : "DDP_Parser"
  pixels     : "PixelDriver_E6804"
  config     : "Config"
  httpServer : "HTTPServer"

VAR
  byte  mac[6]                           ' fixed, not configurable via the web page (per user decision)

  long  portTable[NUM_PORTS * 2]         ' (startChannel, numBytes) pairs, shared by DDP_Parser and PixelDriver
  long  pinTable[NUM_PORTS]              ' pixel data pin per port, same order as portTable

  byte  framebuffer[config#MAX_PIXELS_PER_PORT * NUM_PORTS * 3]   ' sized to the max; config.GetPortNPixels()
                                                                   ' decides how much of each port's slice is used
  byte  rxBuf[RX_BUF_SIZE]

  byte  httpBuf[HTTP_BUF_SIZE]
  long  httpState
  long  httpReqLen
  long  httpHeaderEnd
  long  httpDeadline

PUB Main | bytesRead, greenState

  config.Start(PIN_I2C_SCL, PIN_I2C_SDA)
  config.Load                                                 ' falls back to hardcoded defaults if EEPROM is
                                                                ' blank/corrupt - see Config.spin

  ' Locally-administered MAC (bit 1 of first octet set, per IEEE convention for non-globally-unique addresses).
  ' Fixed, not configurable via the web page - change the last 3 octets if running more than one of these on
  ' the same LAN.
  mac[0] := $02
  mac[1] := $00
  mac[2] := $00
  mac[3] := $00
  mac[4] := $00
  mac[5] := $01

  pinTable[0] := PIN_PIX_J1
  pinTable[1] := PIN_PIX_J2
  pinTable[2] := PIN_PIX_J3
  pinTable[3] := PIN_PIX_J4

  portTable[0] := 0                                          ' J1 start channel (byte offset)
  portTable[1] := config.GetPort1Pixels * 3                   ' J1 byte length
  portTable[2] := portTable[0] + portTable[1]                 ' J2 start channel
  portTable[3] := config.GetPort2Pixels * 3
  portTable[4] := portTable[2] + portTable[3]                 ' J3 start channel
  portTable[5] := config.GetPort3Pixels * 3
  portTable[6] := portTable[4] + portTable[5]                 ' J4 start channel
  portTable[7] := config.GetPort4Pixels * 3

  dira[PIN_LED_RED]~~
  dira[PIN_LED_GREEN]~~
  outa[PIN_LED_RED]~~                                         ' solid red = powered/running, matches stock behavior

  w5200.start(PIN_W5200_CS, PIN_W5200_SCLK, PIN_W5200_MOSI, PIN_W5200_MISO, PIN_W5200_RST)
  w5200.InitAddresses(true, @mac, config.GetGatewayPtr, config.GetSubnetPtr, config.GetIPPtr)
  w5200.SocketOpen(0, w5200#_UDPPROTO, ddp#DDP_PORT, 0, 0)

  w5200.SocketOpen(1, w5200#_TCPPROTO, HTTP_PORT, 0, 0)
  w5200.SocketTCPlisten(1)
  httpState := ST_LISTEN

  ddp.Start(@framebuffer, @portTable, NUM_PORTS)
  pixels.Start(@framebuffer, @portTable, @pinTable)

  greenState := 0

  repeat
    bytesRead := w5200.rxUDP(0, @rxBuf)
    if bytesRead > 8
      if ddp.ProcessPacket(@rxBuf + 8, bytesRead - 8)
        greenState := !greenState
        outa[PIN_LED_GREEN] := greenState                     ' toggles on each accepted DDP frame - activity heartbeat

    PollHTTP

PRI PollHTTP | n, bodyPtr, bodyLen, parsedIP[4], parsedGW[4], parsedSN[4], p1, p2, p3, p4, respLen
'' Non-blocking - called once per main loop iteration alongside the UDP/DDP polling above, same cog, no mutex
'' needed (HTTPServer.spin owns no socket of its own - see its header comment). A GET always gets served the
'' current config form; a POST applies+saves it and REBOOTs so W5200/pixel driver/port table all restart cleanly
'' with the new values instead of trying to live-reinitialize an already-running system.
  case httpState
    ST_LISTEN:
      if w5200.SocketTCPestablished(1)
        httpReqLen := 0
        httpDeadline := cnt + (clkfreq * 5)                   ' bounded abandon-timer - a stuck/slow client can't
        httpState := ST_AWAIT_REQUEST                         ' wedge the listener forever

    ST_AWAIT_REQUEST:
      n := w5200.rxTCP(1, @httpBuf + httpReqLen)
      if n > 0
        httpReqLen += n
        httpHeaderEnd := httpServer.FindHeaderEnd(@httpBuf, httpReqLen)
        if httpHeaderEnd > 0
          if httpServer.IsPOST(@httpBuf)
            bodyLen := httpServer.GetContentLength(@httpBuf, httpHeaderEnd)
            if httpReqLen => (httpHeaderEnd + bodyLen)
              httpState := ST_SERVE
          else
            httpState := ST_SERVE
      elseif (cnt - httpDeadline) > 0
        ResetHTTPSocket

    ST_SERVE:
      if httpServer.IsPOST(@httpBuf)
        bodyPtr := @httpBuf + httpHeaderEnd
        bodyLen := httpReqLen - httpHeaderEnd

        ' pre-fill with current values so a field the form didn't submit keeps its existing value
        bytemove(@parsedIP, config.GetIPPtr, 4)
        bytemove(@parsedGW, config.GetGatewayPtr, 4)
        bytemove(@parsedSN, config.GetSubnetPtr, 4)
        p1 := config.GetPort1Pixels
        p2 := config.GetPort2Pixels
        p3 := config.GetPort3Pixels
        p4 := config.GetPort4Pixels

        httpServer.ParseForm(bodyPtr, bodyLen, @parsedIP, @parsedGW, @parsedSN, @p1, @p2, @p3, @p4)

        config.SetIP(parsedIP[0], parsedIP[1], parsedIP[2], parsedIP[3])
        config.SetGateway(parsedGW[0], parsedGW[1], parsedGW[2], parsedGW[3])
        config.SetSubnet(parsedSN[0], parsedSN[1], parsedSN[2], parsedSN[3])
        config.SetPort1Pixels(p1)
        config.SetPort2Pixels(p2)
        config.SetPort3Pixels(p3)
        config.SetPort4Pixels(p4)
        config.Save

        respLen := httpServer.BuildSavedPage(@httpBuf)
        w5200.txTCP(1, @httpBuf, respLen)
        waitcnt(clkfreq / 2 + cnt)                            ' give the W5200 time to actually queue the response
                                                                ' for send before the chip goes away
        REBOOT
      else
        respLen := httpServer.BuildFormPage(@httpBuf, config.GetIPPtr, config.GetGatewayPtr, config.GetSubnetPtr, config.GetPort1Pixels, config.GetPort2Pixels, config.GetPort3Pixels, config.GetPort4Pixels)
        w5200.txTCP(1, @httpBuf, respLen)
        ResetHTTPSocket

PRI ResetHTTPSocket
  w5200.SocketTCPdisconnect(1)
  w5200.SocketClose(1)
  w5200.SocketOpen(1, w5200#_TCPPROTO, HTTP_PORT, 0, 0)
  w5200.SocketTCPlisten(1)
  httpState := ST_LISTEN
