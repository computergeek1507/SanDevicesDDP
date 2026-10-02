# Hardware & Research Notes

Consolidated from research done 2026-09-27 before writing any firmware. Source docs referenced below are
SanDevices' own published PDFs (E682/E6804 assembly manuals, firmware update procedures) plus Parallax/WIZnet
community resources.

## Confirmed hardware (E682 and E6804 share this core design)

| Part | Component |
|---|---|
| CPU | Parallax Propeller **P8X32A-D40**, socketed 40-pin DIP, pin 1 (notch) faces LEFT (only IC on the board that does) |
| Crystal | 5MHz (Propeller PLL multiplies x16 internally -> 80MHz core clock) |
| Boot EEPROM | Atmel **AT24C1024BPU** (older/Rev<1.3 boards) or ON Semi **24M01** (Rev 1.3+), I2C, standard Propeller boot device. Rev 1.3 boards have jumper J26 to select EEPROM vendor timing. |
| Ethernet | **WIZ820IO** module (WIZnet **W5200** chip), SPI interface, plugs into two 6-pin SIP sockets J23/J24 (12 pins total) |
| Pixel output buffering | 4x 74HCT541 (octal non-inverting buffer, IC5-8, socketed) + 4x 74HCT158 (quad 2:1 mux, IC9-12, soldered) + 8x 270-ohm resistor networks (RN1-2 .. RN15-16) in series with each output line |
| Outputs | E682: 16 pixel ports (J1-J16) + 1 aux power connector (J17). E6804: 4 ports (same family, compact PCB). |
| Programming header | **J20 "PROGRAM"** port, 4-pin — a genuine Parallax Prop Plug header (see below) |
| Status LEDs | 1 Red, 1 Green, 3 Yellow (labelled Rled/Gled/Yled on silkscreen) |

## Programming path (the key finding — no reverse engineering needed)

SanDevices publishes "Updating Firmware with a Parallax Prop Plug Programmer" (sandevices.com/wp-content/uploads/2022/10/Updating-Firmware-with-a-Prop-Plug-Programmer.pdf). It describes:

1. Plug a standard **Parallax Prop Plug** into the board's **PROGRAM port** (board must be powered).
2. Open **Parallax Propeller Tool**, File > Open, set file type to `.eeprom`, open a firmware file.
3. Click **"Load EEPROM"** — takes ~10 seconds.

This confirms:
- The `.eeprom` files SanDevices ships are **plain native Propeller Tool EEPROM images**, not a proprietary/signed format.
- The PROGRAM port follows the **standard Prop Plug pinout** (VDD/RX/TX/VSS in Parallax's usual order) — the doc even says "the Vss pin ... should be designated on the silkscreen ... and also on the programmer. If the programmer is plugged in backwards it won't damage anything," which is the standard Prop Plug reverse-protection behavior.
- We can flash **fully custom firmware** the same way, bypassing SanDevices' LAN update tool (`fwloader_1_0.exe`) and its network protocol entirely. That LAN protocol (documented in `SanDevices_Firmware_Update_Procedure_05-2013.pdf`) is proprietary/undocumented at the byte level and is **not** part of this project's plan.

## What's NOT published anywhere (needs physical tracing)

SanDevices never published a schematic. Unknowns, per board type:
- Which of the Propeller's 32 I/O pins (P0-P31) drive which of the 16 (or 4) physical output ports, through the 74HCT541/158 buffer chain.
- Which Propeller pins connect to the W5200's SPI signals (MOSI, MISO, SCLK, CS/SS, RST, INT) across the 12 pins of J23/J24.
- Exact 4-pin order of J20 (though "standard Prop Plug pinout" narrows this a lot — see `pin_mapping_*.md`).

See `pin_mapping_E682.md` / `pin_mapping_E6804.md` for the tracing procedure and result tables (fill in during Step 2 of the plan).

## Reusable building blocks identified (not yet pulled into this repo)

- **WIZnet W5200 Propeller driver** — exists on Parallax OBEX (obex.parallax.com/obex/wiznet-w5200-driver/). SPI Ethernet driver that runs in its own cog. This is the starting point for `W5200_Driver.spin` instead of writing a raw SPI+TCP/IP stack from scratch.
- **WS2811/WS2812 Propeller driver** — long-running Parallax Forums thread ("WS2811/WS2812 driver for the Propeller", forums.parallax.com/discussion/149456/) with PASM drivers using the standard Propeller technique: bit-bang several pins in parallel from one cog by writing multiple bits of `OUTA` at once inside a cycle-counted loop. This is the model for `PixelDriver_E682.spin` / `PixelDriver_E6804.spin`.
- **DIYLEDExpress "6-port E1.31 bridge"** — architecturally the closest public prior art: Propeller + WIZ820IO board taking E1.31/UDP in and driving pixel outputs out, sold as a kit by diyledexpress.com and documented at maker.wiznet.io/2014/11/28/6-port-e1-31-bridge/ (also referenced from doityourselfchristmas.com's E1.31 Bridge wiki page). **That page returned HTTP 503 during research and could not be fetched** — worth checking again later (maybe via archive.org, which isn't reachable from here) since it may have published Spin source or a schematic directly transferable to this project, especially for the W5200 SPI wiring convention.

## DDP protocol reference (cross-checked against 3 first-party implementations)

See the main plan file and `../src/DDP_Parser.spin` header comment for the full byte layout. Ported from
`C:\software\ESP32P4Pix\main\ddp.c`'s algorithm: DDP uses **absolute byte-offset addressing** into a single
logical channel space for the whole device; each port owns a contiguous sub-range (`startChannel` in ESP32P4Pix's
config model) and a packet can span/overlap multiple ports, so the parser does an interval-overlap copy into each
port's buffer per packet rather than assuming 1 packet = 1 port.

## Actual toolchain: FlexProp, not Propeller Tool

The bring-up ended up using **FlexProp/flexspin** (Total Spectrum's cross-platform P1/P2 toolchain), not the
original Windows-only Parallax Propeller Tool assumed earlier in this doc and the plan file. Matters because
FlexProp defaults to targeting Propeller **2** - for this P8X32A (Propeller 1) board, it must be told to target P1
explicitly, or you get a wall of P2-flavored syntax errors (e.g. "in P2 temporary labels must start with . rather
than :") that have nothing to do with the actual source code.

## Bugs found and fixed during first compile/bring-up (2026-09-30/10-01)

- **Spin1's symbol namespace is file-wide, not scoped like most languages.** CON, VAR, OBJ, PUB/PRI names, method
  parameters, method locals, AND PASM `DAT` labels/`res` variables all share one flat per-file namespace (case-
  insensitive). Two real bugs from this: `PixelDriver_E6804.spin`'s `Start(fbPtr, portTablePtr, pinsPtr)` parameters
  collided with identically-named PASM `res` registers in its own `DAT` section (fixed by renaming the PASM-side
  copies to `fbAddr`/`tblAddr`/`pinAddr`); and `DDP_Parser.spin`'s `VAR packetCount` collided with `PUB
  PacketCount` purely via case-insensitive matching (fixed by renaming the VAR to `pktCount`). Method
  parameters/locals ARE properly scoped *against each other* across different methods (confirmed by the vendored
  W5200 driver reusing `_socket` as a parameter name in ten different methods) - the restriction is specifically
  against VAR/CON/OBJ/DAT-level global symbols.
- **`if_nb` is not a real P1 PASM condition mnemonic** (unlike `if_b`, which is) - FlexProp silently treated its
  first occurrence as a label definition instead of a condition prefix, meaning the guarded instruction was
  executing unconditionally (a real logic bug, not just a compile error, since only the 2nd+ occurrences actually
  errored). Fixed by using the base flag-test mnemonic `if_nc` ("if no carry") instead of the `b`/`nb`
  ("below"/"not below") alias pair - `if_b` by itself was fine, only the "not" form wasn't recognized.
- **PASM immediates are 9-bit (0-511) only.** `RESET_CYC = 4800` doesn't fit in a `#literal` operand ("Source
  operand too big for add") - fixed by stashing it in an initialized `DAT` `long` and referencing that directly
  (no `#`) instead of as an immediate.
- Compiling a sub-object file directly (e.g. `PixelDriver_E6804.spin` on its own) instead of the top-level
  `Main.spin` "works" (no error) but does nothing useful - FlexProp just runs that file's first `PUB` as an
  entry point with garbage arguments. Always compile/upload `Main.spin`.

## Pixel protocol correction: APA102/SK9822, not WS2811

The E6804's output connectors turned out to have a **dedicated clock pin per port** (traced: J1=P21, J2=P22,
J3=P20, J4=P19, alongside the data pins J1=P0/J2=P4/J3=P8/J4=P12 - see `pin_mapping_E6804.md`), confirming these
boards drive 2-wire clocked pixel chips (APA102/SK9822), not single-wire WS2811/WS2812 as first assumed.
`PixelDriver_E6804.spin` was rewritten accordingly. Clocked protocols have no tight pulse-width timing requirement
(receiver samples on clock edges, not pulse duration), so the rewrite sends all 4 ports sequentially from one cog
instead of needing WS2811's parallel-lockstep bit-bang technique - simpler code, and still fast enough for a normal
pixel-display frame rate at a conservative ~1MHz clock pace.

## W5200 bring-up troubleshooting (in progress, 2026-10-01)

`Main.spin` compiles clean, loads to RAM, and the red status LED confirms execution starts. Added green-LED
blink-count checkpoints after each startup call (`w5200.start`, `InitAddresses`, `SocketOpen`, `ddp.Start`,
`pixels.Start`) - **all 5 pass**, meaning every Spin-level call returns without hanging. Despite that, the
WIZ820IO module's own link LED never lights, even with:
- Power, cable, and module seating all confirmed good
- RST pin confirmed at 3.3V (released, not stuck in reset) via multimeter
- MOSI/MISO swapped as an experiment (no change either way - reverted)

**Resolved: it was the Ethernet cable.** Swapping cables brought the WIZ820IO's link LED up immediately - nothing
wrong with the board, the traced pins, or the firmware. All the software-side checkpoints (5/5 passing, RST reading
3.3V) were correctly reporting that the code was fine the whole time; the fault was purely physical-layer and
outside anything traceable from the Propeller side. Worth remembering for next time: a dead/marginal cable produces
symptoms that look exactly like a deeper hardware or SPI-pin problem (no link LED, no response) even though
everything upstream of the cable is working correctly - cheap to rule out, should've been step zero.

## Firmware update safety

Before flashing anything custom to a board's own EEPROM: back up the stock firmware first if possible (Propeller
Tool doesn't provide EEPROM readback by default the way it does write, so the safer path is to keep the *original
Propeller chip* as the backup — pull it, socket a spare P8X32A for all custom-firmware bring-up and testing, and
only move to the original board's own chip once the firmware is proven on the bench).
