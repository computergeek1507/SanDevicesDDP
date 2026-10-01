# SanDevicesDDP

Custom Spin/PASM firmware for SanDevices E682 (16-port) and E6804 (4-port) LED pixel controllers, replacing the
stock firmware with a DDP receiver plus a basic web config page. Both boards use a socketed Parallax Propeller
P8X32A and a WIZ820IO (WIZnet W5200) Ethernet module, and are flashed over their PROGRAM header with a standard
Parallax Prop Plug and Propeller Tool — see `docs/NOTES.md` for how that was confirmed and why no reverse
engineering of SanDevices' own tools/protocol was needed.

Full plan: `C:\Users\scoot\.claude\plans\wiggly-baking-clock.md`

## Status

| Step | State |
|---|---|
| 1. Toolchain bring-up (Prop Plug + Propeller Tool) | Not started - user needs to buy a Prop Plug and install Propeller Tool |
| 2. Pin-mapping discovery (multimeter tracing) | **E6804 traced** - see `docs/pin_mapping_E6804.md`. E682 not started - see `docs/pin_mapping_E682.md` |
| 3. W5200 Ethernet cog | **Done for E6804**: vendored the real OBEX driver (`src/W5200_Driver.spin`, see `vendor/W5200_Driver/PROVENANCE.md`) and wired it up in `src/Main.spin` against the traced SPI pins |
| 4. DDP receiver + parser | **Done**: `src/DDP_Parser.spin` - hardware-independent, not yet compiled/tested |
| 5. Pixel output cog(s) | **Done for E6804**: `src/PixelDriver_E6804.spin` (4-port parallel WS2811 bit-bang). E682's 16-port version not started - needs `docs/pin_mapping_E682.md` traced first |
| 6. Config storage + web page | Not started - `src/Main.spin` currently has network/pixel-count config as fixed compile-time constants |
| 7. Integration | **First pass done**: `src/Main.spin` wires W5200 + DDP_Parser + PixelDriver_E6804 together for the E6804 board. Not yet compiled, flashed, or bench-tested - no Propeller toolchain available in this environment |

## Why start with the parser

`DDP_Parser.spin` needs no pin knowledge at all - it just turns a UDP payload pointer into writes on a hub-RAM
frame buffer via a caller-supplied port table (start channel + length per port). That made it safe to write before
any hardware tracing was done. Everything else in this repo was gated on `docs/pin_mapping_E682.md` /
`pin_mapping_E6804.md` being filled in, because PASM pin masks for both the pixel driver and the W5200 SPI driver
have to be right the first time.

## Current state (E6804)

All four pieces for the E6804 exist and are wired together in `src/Main.spin`:
`W5200_Driver` (vendored, real Parallax community object, not reinvented) → `DDP_Parser` (hand-written, ported
from the validated algorithm in `ESP32P4Pix/main/ddp.c`) → shared hub-RAM frame buffer → `PixelDriver_E6804`
(hand-written 4-port parallel WS2811 PASM driver). Network IP and per-port pixel counts are compile-time constants
in `Main.spin` for now (edit `PORT1_PIXELS`..`PORT4_PIXELS` to match your actual strings).

**None of this has been compiled or run** - there's no Propeller toolchain in this environment. Next action is
still Step 1 (buy a Prop Plug, install Propeller Tool) so the code above can actually be built and verified against
real hardware, cog by cog, per the plan's verification section.

## E682 (16-port)

Not started. `docs/pin_mapping_E682.md` needs the same multimeter tracing pass the E6804 got before
`PixelDriver_E682.spin` can be written - don't assume the pin numbers match, trace it separately.

## Remaining work

- Bring up and verify each cog on real E6804 hardware (Step 1 unblocks this)
- Trace the E682 and write `PixelDriver_E682.spin` (same pattern as the E6804 one, just 16 pins instead of 4 -
  probably needs more than one cog since a Propeller cog realistically drives a handful of parallel WS2811 outputs
  well within timing budget, not 16 at once - worth revisiting the port-per-cog split once E682 pins are known)
- `Config.spin` (EEPROM-backed config, replacing the fixed constants in `Main.spin`) and `HTTPServer.spin` (basic
  web config page) - Step 6, not started
