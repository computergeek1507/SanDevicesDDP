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
| 5. Pixel output cog(s) | **Confirmed working on real hardware**: `src/PixelDriver_E6804.spin` (the real 4-port driver) correctly lights pixels red via `test/Pixel_Red_Test.spin`. Two real PASM timing bugs and a byte-order mismatch found and fixed along the way - see `docs/NOTES.md`. Board also has real APA102/SK9822-capable clock pins traced, planned as a follow-up dual-mode addition. E682's 16-port version not started |
| 6. Config storage + web page | **In progress - partially verified on real hardware.** `src/Config.spin` (EEPROM-backed IP/gateway/subnet/per-port pixel counts - MAC and DDP port are fixed, not configurable) + `src/HTTPServer.spin` (minimal config web page) wired into `src/Main.spin`; saving applies changes live (pixel driver restart + W5200 address registers rewritten) with no reboot - an earlier reboot-based design was tried and found unreliable on real hardware (see `docs/NOTES.md`). EEPROM roundtrip and loading the page with defaults are confirmed; the live-apply save path is not yet confirmed |
| 7. Integration | **Done** - full live path confirmed on real hardware: a real DDP packet through `Main.spin` -> `DDP_Parser` -> shared frame buffer -> `PixelDriver_E6804` correctly lit J2/J3 red. (J1 has a known-dead pin, unrelated to this firmware - see `docs/NOTES.md`.) |
| 8. DMX512 output mode | Requested, not started - see caveat in `docs/NOTES.md` about this board having no RS-485 transceiver, so it'd be logic-level DMX framing, not electrically-real DMX512 |
| 9. APA102/SK9822 dual-mode pixel output | Requested, not started - board's per-port clock pins are real and traced; needs actual APA102/SK9822 hardware to test against, and a second PASM cog (separate from the WS2812 one - the two protocols' timing doesn't mix well in one cog) |

## Hardware bring-up status (E6804)

**Network path fully confirmed on real hardware**: `Main.spin` compiles clean under FlexProp, loads to RAM, the
W5200 comes up (link LED on, replies to ping at `192.168.5.206` - adjust `IP0`..`SUB3` in `Main.spin` to match your
own LAN), and sending a test packet with `tools/send_test_ddp.py` makes the green activity LED toggle, confirming
`DDP_Parser.spin` is correctly accepting real packets end-to-end.

**Pixel output is now confirmed working on real hardware** - `test/Pixel_Red_Test.spin` (the actual
`PixelDriver_E6804.spin` firmware object, hardcoded to 10 red pixels on J1) shows correct red. Getting there took
finding and fixing two real PASM timing bugs and a byte-order mismatch (this pixel wants plain R,G,B, not the G,R,B
order many WS2812 chips use) - see `docs/NOTES.md` for the full story, including an earlier false "it worked"
report that sent debugging in the wrong direction for a while (worth a read for the lesson on re-confirming
hardware results).

**The full live path through `Main.spin` is now confirmed end-to-end on real hardware** - `tools/send_test_ddp.py
192.168.5.206 255 0 0 400` (a `pixel_count` large enough to span past J1's byte range) correctly lit J2/J3 red via
`DDP_Parser` -> shared frame buffer -> `PixelDriver_E6804`. J1 separately turned out to have a dead/faulty pin
(confirmed via `test/Pin_Range_Test.spin` - P0 doesn't toggle at all, even with plain GPIO and no PASM timing
involved), unrelated to any of the driver/parser code - see `docs/NOTES.md` for the full diagnosis (including an
open question there about why 400 was needed, not the smaller value the port byte-math suggested should suffice).

## Why start with the parser

`DDP_Parser.spin` needs no pin knowledge at all - it just turns a UDP payload pointer into writes on a hub-RAM
frame buffer via a caller-supplied port table (start channel + length per port). That made it safe to write before
any hardware tracing was done, and it's now the first piece confirmed working end-to-end on real hardware.

## E682 (16-port)

Not started. `docs/pin_mapping_E682.md` needs the same multimeter tracing pass the E6804 got (data pins, clock
pins, LEDs, W5200 SPI) before `PixelDriver_E682.spin` can be written - don't assume the pin numbers match, trace it
separately.

## Remaining work

- Verify Config storage + web page (Step 6) on real hardware - it currently only has "compiles clean" behind it,
  not an actual hardware test. See the checklist in `docs/NOTES.md` / the plan file.
- Swap in a spare P8X32A chip to recover J1 (P0 doesn't toggle on the current chip - see `docs/NOTES.md`), or
  confirm it's a socket/board fault instead if a replacement chip doesn't fix it either
- Add APA102/SK9822 dual-mode pixel output (requested) once real APA102/SK9822 hardware is available to test -
  needs a second PASM cog, not merged into the WS2812 one
- Add a DMX512 output mode (requested) - likely a separate small driver object, selectable per port
- Trace the E682 and write `PixelDriver_E682.spin` (same pattern, 16 ports instead of 4 - probably needs more than
  one cog)
- `Config.spin` (EEPROM-backed config, replacing the fixed constants in `Main.spin`) and `HTTPServer.spin` (basic
  web config page) - Step 6, not started
