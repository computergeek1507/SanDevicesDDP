{{
  W5200_Reboot_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware. Isolates one question: does the W5200 come back
  up after a Propeller-only REBOOT (no board power cycle), with NONE of Config.spin/HTTPServer.spin/DDP_Parser in
  the picture at all - just w5200.start/InitAddresses/SocketOpen(UDP), a visible link-up indicator, then REBOOT.

  Purpose: `Main.spin`'s config-save flow calls REBOOT after serving the "Saved" page over TCP, and twice now the
  board has come back with the Propeller clearly running (solid red LED) but the W5200 completely unresponsive (no
  ping, no green activity LED, needing a full power cycle to recover) - even after widening the W5200 reset pulse
  400x (see docs/NOTES.md). This test removes every other moving part to answer: is this REBOOT-vs-W5200 in
  general, or something specific to the HTTP/TCP code path in Main.spin's POST handler?

  Behavior: brings up the W5200 on a UDP socket (same pattern as Main.spin, same IP/gateway/subnet/MAC as the
  defaults), blinks the green LED 3 times to mark "about to reboot" (so you can tell when it's restarting vs.
  still in its first run), waits 3 seconds, then REBOOTs. Repeats forever - run it and watch whether the green
  LED keeps blinking 3x every few seconds after each reboot (W5200 survives REBOOT) or goes dark after the first
  reboot and never blinks again (confirms the problem is REBOOT itself, not the HTTP code path) - in BOTH cases,
  also try pinging the board's IP a few seconds after a reboot to confirm independently of the LED.
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
  outa[PIN_LED_RED]~~                    ' solid red = running, same convention as Main.spin

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

  ' mark "alive and about to reboot" with 3 green blinks - if the W5200 survives a REBOOT, you should see this
  ' repeat every few seconds forever; if it only happens ONCE and never again, the W5200 didn't come back
  BlinkGreen(3)

  waitcnt(clkfreq * 3 + cnt)
  REBOOT

PRI BlinkGreen(n) | i
  repeat i from 1 to n
    outa[PIN_LED_GREEN]~~
    waitcnt(clkfreq / 4 + cnt)
    outa[PIN_LED_GREEN]~
    waitcnt(clkfreq / 4 + cnt)
