# SanDevicesDDP

Custom Spin/PASM firmware for SanDevices E682 (16-port) and E6804 (4-port) LED pixel controllers, replacing the
stock firmware with a DDP receiver plus a basic web config page. Both boards use a socketed Parallax Propeller
P8X32A and a WIZ820IO (WIZnet W5200) Ethernet module, and are flashed over their PROGRAM header with a standard
Parallax Prop Plug - see `docs/NOTES.md` for how that was confirmed, why no reverse engineering of SanDevices' own
tools/protocol was needed, and the toolchain/compiler gotchas hit along the way (actual toolchain in use is
FlexProp/flexspin, not the original Propeller Tool first assumed).

Full plan: `C:\Users\scoot\.claude\plans\wiggly-baking-clock.md`

Repo: https://github.com/computergeek1507/SanDevicesDDP

## Status

| Step | State |
|---|---|
| 1. Toolchain bring-up (Prop Plug + FlexProp) | **Done** - confirmed via `test/Blink_Test.spin` and now `Main.spin` on real hardware |
| 2. Pin-mapping discovery (multimeter tracing) | **E6804 fully traced**, including pixel data *and* clock pins - see `docs/pin_mapping_E6804.md`. E682 not started |
| 3. W5200 Ethernet cog | **Confirmed working on real hardware**: link LED up, ping replies, DDP packets received (green activity LED toggles) - see `tools/send_test_ddp.py` |
| 4. DDP receiver + parser | **Confirmed working on real hardware**: `src/DDP_Parser.spin` accepts real DDP packets sent to the board |
| 5. Pixel output cog(s) | **In progress for E6804**: `src/PixelDriver_E6804.spin` is single-wire WS2812/WS2811 (matching the test strip on hand), not yet confirmed working on hardware. Board also has real APA102/SK9822-capable clock pins traced, planned as a follow-up dual-mode addition. E682's 16-port version not started |
| 6. Config storage + web page | Not started - `src/Main.spin` currently has network/pixel-count config as fixed compile-time constants |
| 7. Integration | **Network path fully proven on hardware.** Pixel output is the remaining unverified piece |
| 8. DMX512 output mode | Requested, not started - see caveat in `docs/NOTES.md` about this board having no RS-485 transceiver, so it'd be logic-level DMX framing, not electrically-real DMX512 |
| 9. APA102/SK9822 dual-mode pixel output | Requested, not started - board's per-port clock pins are real and traced; needs actual APA102/SK9822 hardware to test against, and a second PASM cog (separate from the WS2812 one - the two protocols' timing doesn't mix well in one cog) |

## Hardware bring-up status (E6804)

**Network path fully confirmed on real hardware**: `Main.spin` compiles clean under FlexProp, loads to RAM, the
W5200 comes up (link LED on, replies to ping at `192.168.5.206` - adjust `IP0`..`SUB3` in `Main.spin` to match your
own LAN), and sending a test packet with `tools/send_test_ddp.py` makes the green activity LED toggle, confirming
`DDP_Parser.spin` is correctly accepting real packets end-to-end.

**Pixel output is the remaining open item.** It briefly went through an APA102/SK9822 2-wire detour after tracing
found real clock pins per port, but the bench pixel strip turned out to be WS2812 (single-wire, no clock input), so
`PixelDriver_E6804.spin` is back to single-wire WS2812/WS2811 timing to match what's actually testable right now.
Not yet confirmed working on hardware - see `docs/NOTES.md` for the full back-and-forth and `test/APA102_Pin_Test.spin`
for an isolated GPIO-toggle sanity check if pixel output still doesn't behave once tested.

## Why start with the parser

`DDP_Parser.spin` needs no pin knowledge at all - it just turns a UDP payload pointer into writes on a hub-RAM
frame buffer via a caller-supplied port table (start channel + length per port). That made it safe to write before
any hardware tracing was done, and it's now the first piece confirmed working end-to-end on real hardware.

## E682 (16-port)

Not started. `docs/pin_mapping_E682.md` needs the same multimeter tracing pass the E6804 got (data pins, clock
pins, LEDs, W5200 SPI) before `PixelDriver_E682.spin` can be written - don't assume the pin numbers match, trace it
separately.

## Remaining work

- Confirm WS2812 pixel output actually works on real hardware (the one piece not yet verified)
- Add APA102/SK9822 dual-mode pixel output (requested) once real APA102/SK9822 hardware is available to test -
  needs a second PASM cog, not merged into the WS2812 one
- Add a DMX512 output mode (requested) - likely a separate small driver object, selectable per port
- Trace the E682 and write `PixelDriver_E682.spin` (same pattern, 16 ports instead of 4 - probably needs more than
  one cog)
- `Config.spin` (EEPROM-backed config, replacing the fixed constants in `Main.spin`) and `HTTPServer.spin` (basic
  web config page) - Step 6, not started
