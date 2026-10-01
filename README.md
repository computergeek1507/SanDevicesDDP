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
| 1. Toolchain bring-up (Prop Plug + FlexProp) | **Done** - FlexProp compiles and RAM-loads successfully; confirmed via `test/Blink_Test.spin` and now `Main.spin` |
| 2. Pin-mapping discovery (multimeter tracing) | **E6804 fully traced**, including pixel data *and* clock pins (see below) - see `docs/pin_mapping_E6804.md`. E682 not started - see `docs/pin_mapping_E682.md` |
| 3. W5200 Ethernet cog | **Done for E6804**: vendored the real OBEX driver (`src/W5200_Driver.spin`, see `vendor/W5200_Driver/PROVENANCE.md`), wired up in `src/Main.spin`. Network bring-up (ping test) in progress |
| 4. DDP receiver + parser | **Done**: `src/DDP_Parser.spin` - hardware-independent, compiles clean |
| 5. Pixel output cog(s) | **Done for E6804, corrected**: `src/PixelDriver_E6804.spin` now drives APA102/SK9822-style 2-wire (clock+data) pixels, not WS2811 - tracing found a dedicated clock pin per port. E682's 16-port version not started |
| 6. Config storage + web page | Not started - `src/Main.spin` currently has network/pixel-count config as fixed compile-time constants |
| 7. Integration | **Compiles and runs on real hardware**: `Main.spin` loads to RAM, red status LED confirmed lighting (execution reaches past W5200 setup). Network and pixel-output verification still in progress |
| 8. DMX512 output mode | Requested, not started - see caveat in `docs/NOTES.md` about this board having no RS-485 transceiver, so it'd be logic-level DMX framing, not electrically-real DMX512 |

## Hardware bring-up status (E6804)

Real progress on real hardware, not just source: `Main.spin` compiles clean under FlexProp and loads to RAM, and
the red status LED (P17) lights up as expected, confirming execution gets past VAR setup and the W5200 init calls
without hanging or crashing. Next checkpoint is a ping test to `192.168.1.206` to confirm the W5200/network side
came up correctly, then an actual DDP packet to confirm the full receive pipeline, then real pixel output
(corrected to APA102/SK9822 2-wire framing - see `docs/NOTES.md`).

## Why start with the parser

`DDP_Parser.spin` needs no pin knowledge at all - it just turns a UDP payload pointer into writes on a hub-RAM
frame buffer via a caller-supplied port table (start channel + length per port). That made it safe to write before
any hardware tracing was done. Everything else in this repo was gated on `docs/pin_mapping_E682.md` /
`pin_mapping_E6804.md` being filled in.

## E682 (16-port)

Not started. `docs/pin_mapping_E682.md` needs the same multimeter tracing pass the E6804 got (data pins, clock
pins, LEDs, W5200 SPI) before `PixelDriver_E682.spin` can be written - don't assume the pin numbers match, trace it
separately.

## Remaining work

- Finish E6804 network + pixel-output bring-up (ping test, real DDP packet test, verify APA102 framing against a
  logic analyzer or actual strings)
- Add a DMX512 output mode (requested) - likely a separate small driver object, selectable per port
- Trace the E682 and write `PixelDriver_E682.spin` (same pattern, 16 ports instead of 4 - probably needs more than
  one cog)
- `Config.spin` (EEPROM-backed config, replacing the fixed constants in `Main.spin`) and `HTTPServer.spin` (basic
  web config page) - Step 6, not started
