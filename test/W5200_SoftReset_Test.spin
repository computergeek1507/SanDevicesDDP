{{
  W5200_SoftReset_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Tests whether W5200_Driver.spin's ResetSoftware
  (writes the W5200's Mode Register reset bit over SPI - no external RST pin involved at all) can reliably bring
  the chip back up WITHOUT ever rebooting the Propeller - unlike test/W5200_Reboot_Test.spin, which showed the
  W5200 doesn't reliably survive a Propeller-only REBOOT even with a widened hardware-reset pulse (see
  docs/NOTES.md). This matters because the original SanDevices stock firmware can change the board's IP live,
  without the user power-cycling - so a Propeller-only chip-level software reset, if reliable, would let us do
  the same, instead of deferring IP/gateway/subnet changes to the next reboot.

  Also exercises the just-added bounded (2-second) timeout on WriteIPaddress/WriteGatewayAddress/WriteSubnetMask/
  ResetSoftware/ResetHardware/WriteMACaddress - these used to block forever if the ASM cog never serviced the
  command, which is suspected to be exactly what hung the whole firmware when Main.spin tried calling
  WriteIPaddress live for the first time (see docs/NOTES.md). If that bound is working, this test can never hang
  the whole board even if ResetSoftware/InitAddresses turn out not to work reliably here either - worst case each
  cycle takes a few extra seconds, not forever.

  Behavior: brings up the W5200 (same IP/gateway/subnet/MAC as Main.spin's defaults), blinks green 3x, waits 3s,
  then - WITHOUT rebooting the Propeller at all - closes the UDP socket, calls ResetSoftware, re-runs
  InitAddresses, reopens the UDP socket, blinks green 5x (a DIFFERENT count than the first blink, so you can tell
  "survived a soft-reset cycle" apart from "first boot"), waits 3s, and repeats forever. Watch for: does the 5-blink
  pattern keep repeating indefinitely (soft reset + reinit is reliable), or does it blink 5x once and then stop
  (unreliable, same class of problem as the REBOOT case) - and ping the board's IP a few seconds after each cycle
  to confirm independently of the LED.
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  PIN_LED_GREEN  = 16
  PIN_LED_RED    = 17

  PIN_W5200_MISO = 23
  PIN_W5200_MOSI = 24
  PIN_W5200_RST  = 25
  PIN_W5200_CS   = 26
  PIN_W5200_SCLK = 27

  DDP_PORT = 4048

OBJ
  w5200 : "../src/W5200_Driver"

VAR
  byte mac[6]
  byte gateway[4]
  byte subnet[4]
  byte myip[4]

PUB Main

  dira[PIN_LED_RED]~~
  dira[PIN_LED_GREEN]~~
  outa[PIN_LED_RED]~~                    ' solid red = running, never touched again - if this ever goes dark,
                                          ' the Propeller itself crashed/reset, not just the W5200

  mac[0] := $02
  mac[1] := $00
  mac[2] := $00
  mac[3] := $00
  mac[4] := $00
  mac[5] := $01

  gateway[0] := 192
  gateway[1] := 168
  gateway[2] := 5
  gateway[3] := 1

  subnet[0] := 255
  subnet[1] := 255
  subnet[2] := 255
  subnet[3] := 0

  myip[0] := 192
  myip[1] := 168
  myip[2] := 5
  myip[3] := 206

  w5200.start(PIN_W5200_CS, PIN_W5200_SCLK, PIN_W5200_MOSI, PIN_W5200_MISO, PIN_W5200_RST)
  w5200.InitAddresses(true, @mac, @gateway, @subnet, @myip)
  w5200.SocketOpen(0, w5200#_UDPPROTO, DDP_PORT, 0, 0)

  BlinkGreen(3)                          ' first boot marker
  waitcnt(clkfreq * 3 + cnt)

  repeat
    w5200.SocketClose(0)
    w5200.ResetSoftware(true)            ' SPI-only reset - no external pin, Propeller never reboots
    w5200.InitAddresses(true, @mac, @gateway, @subnet, @myip)
    w5200.SocketOpen(0, w5200#_UDPPROTO, DDP_PORT, 0, 0)

    BlinkGreen(5)                       ' "survived a soft-reset cycle" marker - repeating = reliable
    waitcnt(clkfreq * 3 + cnt)

PRI BlinkGreen(n) | i
  repeat i from 1 to n
    outa[PIN_LED_GREEN]~~
    waitcnt(clkfreq / 4 + cnt)
    outa[PIN_LED_GREEN]~
    waitcnt(clkfreq / 4 + cnt)
