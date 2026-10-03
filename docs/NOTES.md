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

**Follow-up (2026-10-01): reverted back to single-wire WS2812/WS2811 for now.** The clock pins traced above are
real and the board genuinely supports driving APA102/SK9822-style 2-wire pixels - but testing the APA102 driver
against the actual bench pixel strip produced a stuck white/unresponsive LED, and it turned out the test strip was
WS2812 (single-wire, no clock input at all) the whole time, not APA102/SK9822. A WS2812 LED with nothing valid on
its single data line commonly defaults to showing white/garbage, which is exactly what was observed - the "bug"
was a mismatched test setup, not necessarily the APA102 driver logic (that was never actually validated against
real APA102/SK9822 hardware either way). `PixelDriver_E6804.spin` is back to single-wire WS2812/WS2811 timing
(800kHz-class, matching WS2812 specifically) so it matches what's actually testable right now. The user wants to
support both pixel types eventually - planned as a second, separate PASM cog dedicated to APA102/SK9822 ports once
real APA102/SK9822 hardware is on hand to validate against, rather than merging both protocols' very different
timing models into one cog. `test/APA102_Pin_Test.spin` (a plain 1Hz GPIO toggle on the data/clock pins, no PASM
timing involved) is still in the repo as a quick wiring sanity check if pixel output misbehaves again.

**Correction (2026-10-01): pixel output was never actually confirmed working.** An earlier note (and a few hours of
debugging direction) was based on a user report of "it lit up" / "it's P0" from `test/WS2812_Pin_Scanner.spin`,
which turned out to be a mistaken report - it never actually worked, on any test, on any pin, with either pixel
tried. Lesson for next time: when a hardware result is the only evidence a fix worked, it's worth a quick
re-confirmation ("just to double check - you definitely saw red, not white/nothing?") before building further
debugging direction on top of it, especially after a long back-and-forth where a quick yes/no answer is easy to
give on autopilot.

**Follow-up (2026-10-01): found two separate real timing bugs, not one.** First, in the 4-port parallel driver:
`bitloop` captured its timing reference (`mov time,cnt`) at the TOP of the loop, before computing
`activemask`/`zeromask` across all 4 ports (8 conditional cmp/test instructions, ~60+ cycles) - so by the time
execution reached the first `waitcnt`, real elapsed time had already blown past the intended T0H deadline (32
cycles). Fixed by moving the `activemask`/`zeromask` computation BEFORE capturing the timing reference.

Second, and more fundamental - present in ALL versions including the single-pin test files, and only found by
re-deriving the cycle count by hand after the "it worked" report turned out to be false: every `clockByte` routine
had a `mov time,cnt` / `add time,#40` pair, intending "40 cycles of lead-in margin" before the first `waitcnt` -
but the pin was being set high (`or outa,curMask`) on the very next instruction, with no actual `waitcnt` in
between to consume those 40 cycles. So the pin's real high transition happened only ~4-8 cycles after reading
`cnt`, while every subsequent T0H/T1H/period deadline was calculated as if it happened 40 cycles later. Net effect:
every single pulse (0-bit and 1-bit alike) was stretched by roughly 40 extra cycles (~500ns) - turning the intended
~0.4us/0.8us WS2812 pulses into something like ~0.75us/1.15us, well outside what the chip can reliably tell apart,
and consistent with "always white/garbage, every test, every pin, every pixel tried" rather than an intermittent
or pin-specific fault. Fixed by capturing `time := cnt` immediately before the single instruction that actually
changes the pin, with nothing but that one instruction in between - not before an unwaited-for delay.

Lesson: in PASM timing loops, capture your `cnt` reference as close as possible to the action being timed, after
all variable-cost preparatory work, not before it.

**Resolved (2026-10-01): WS2812 pixel output confirmed working on real hardware, properly this time.** After the
"+40 phantom lead-in" fix, `test/WS2812_Static_Red.spin` (hardcoded single pixel, P0) first showed **green**
instead of red - progress, since green/stable-color means the chip is now decoding valid timing data at all,
versus the white/garbage seen in every prior attempt. Green instead of red meant this specific pixel reads incoming
bytes as plain **R,G,B order**, not the G,R,B order many WS2812 chips use - swapping the byte order in the test
(send R first, not G first) produced a correct, confirmed **red** pixel. `PixelDriver_E6804.spin` already passes
bytes through unmodified (no reordering), and since R,G,B happens to match DDP's conventional RGB8 sender order
already, no firmware change was needed there for color order - only the timing fixes above.

**Confirmed (2026-10-01): the real 4-port `PixelDriver_E6804.spin` works on hardware.** `test/Pixel_Red_Test.spin`
(hardcodes 10 red pixels on J1, bypassing W5200/DDP entirely, using the actual firmware pixel driver object) showed
correct red on J1. Both PASM timing bugs and the byte-order fix are now validated in the real 4-port driver, not
just the isolated single-pin test files. Remaining step to close the loop entirely: the full path through
`Main.spin` (real DDP packet -> `DDP_Parser` -> shared frame buffer -> `PixelDriver_E6804` -> visible pixels), which
exercises the same driver with live network data instead of a hardcoded buffer.

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

## P0 hardware fault found (2026-10-02) - explains every WS2812 "doesn't work" report

After `test/WS2812_Static_Red.spin` (the absolute-minimal single-pixel test, freshly RAM-loaded, board not
power-cycled in between) showed **completely dark** with no code changes from its previously-reported-working
state, escalated to `test/Pin_Range_Test.spin` (plain `dira`/`outa` toggle of P0-P15 together, 1Hz, no PASM/timing
at all) to separate "software/timing bug" from "something more fundamental." Result: **P0 does not toggle; P4 and
P8 do**, probed directly on the P8X32A's own DIP pin (not at the board's J1 connector), so the board's
74HCT541/158 buffer-and-mux chain was never in the measurement path.

Since `Pin_Range_Test.spin` flips all 16 pins with one `outa` write (not a per-pin code path), this rules out a
software/pin-selection bug entirely - 15 other pins toggling correctly on the same instruction, same cog, same
run, while P0 alone doesn't, points at a **hardware fault specific to P0 on this physical Propeller chip** (or,
less likely, a bad socket contact at that one pin).

**This retroactively explains every WS2812 test failure on P0 to date**, including the "confirmed working, properly
this time" report from 2026-10-01 above - that result may have been a brief genuine success before P0 failed (e.g.
from damage during bring-up, such as driving a WS2812 data line directly without the board's normal series
resistor if that test was wired as a direct bypass rather than through J1), or may itself have been another
mistaken/unreliable report, consistent with this project's prior "it worked" false-positive (see the 2026-10-01
correction above). Either way, none of the WS2812 driver PASM logic (single-pin or 4-port) should be considered
suspect from this symptom - the dark-pixel reports were a P0 hardware problem, not a timing/logic bug.

**Next step (not yet done): swap in a spare P8X32A chip** (the board's CPU is socketed specifically to allow this -
see "Firmware update safety" below) and re-run `test/Pin_Range_Test.spin`, checking P0 again on the new chip. If P0
toggles on the replacement chip, this chip's P0 I/O driver is damaged and it should be set aside; if P0 still
doesn't toggle with a different chip in the socket, suspect the socket's P0 contact or a board trace, not the chip.
Once P0 toggles on some known-good chip/socket combination, re-test `test/WS2812_Static_Red.spin` on that same
setup before trusting any WS2812 timing result again.

**Confirmed, not a software issue (2026-10-02):** revisited an earlier `test/Pixel_Red_Test_4Port.spin` run where
"port 2 turned red" had been read as a working result worth worrying about alongside the new P0 failure. Port 2 is
**J2 = P4** (not P0) - and J3 (P8) also lit correctly in that same run, while J1 (P0) did not. This matches
`Pin_Range_Test.spin`'s result exactly (P4/P8 toggle, P0 doesn't) and confirms the pixel driver PASM - both the
single-pin version and the real 4-port `PixelDriver_E6804.spin` - has been working correctly on every healthy pin
all along. The only fault is the dead/faulty P0 line itself; nothing in the WS2812 timing or driver logic needs
further suspicion from this symptom.

**Confirmed (2026-10-02): full live path through `Main.spin` works on real hardware.** Sending a real DDP packet via
`tools/send_test_ddp.py 192.168.5.206 255 0 0 400` (1200 bytes from offset 0) correctly lit J2/J3 red end-to-end:
W5200 receive -> `DDP_Parser.ProcessPacket` -> shared frame buffer -> `PixelDriver_E6804` -> visible pixels. This
closes the last open item from the plan/README status table.

Note the default CLI usage (`pixel_count=10`, offset always 0) only ever touches J1's byte range (0-149) - with
J1's pin dead, a default-arguments test run looks like "nothing happened," which isn't a bug, just not enough
pixels requested to spill into another port's range.

Open question: with all 4 ports at 50 pixels each (150 bytes/port, 600 bytes total), `pixel_count=200` (600 bytes)
should mathematically be enough to span all 4 ports' ranges per `DDP_Parser.spin`'s interval-overlap math, but 400
(1200 bytes - double the buffer's actual total size) is the value that was confirmed working; smaller values
weren't methodically bisected. `rxUDP` in `W5200_Driver.spin` doesn't show an obvious size cap that would explain
needing double (it reads the full packet length from the UDP header, well under the W5200's 2KB per-socket RX
buffer) - worth bisecting the actual minimum (try 200, 250, 300...) if it matters for real usage, since xLights/DDP
senders will send whatever size the sequence dictates, not a hand-picked safe value.

## Config storage + web page (Step 6) - implemented, not yet tested on real hardware (2026-10-02)

Added `src/I2C_EEPROM.spin` (plain-Spin bit-banged I2C, P28/P29 - the Propeller's own default boot pins, confirmed
unchanged on this board via `docs/pin_mapping_E6804.md`), `src/Config.spin` (EEPROM-backed settings: MAC/IP/
gateway/subnet, DDP port, per-port pixel counts), and `src/HTTPServer.spin` (minimal GET-form/POST-save config
page), wired into `src/Main.spin`. Everything below is confirmed by **compiling with the real toolchain**
(`flexspin`) - none of it has been run on the actual board yet, so treat it as "should work" not "works" until
the verification checklist below is actually done on hardware.

**EEPROM layout**: one 42-byte block at offset `$8000` (32768) - magic+version+MAC+IP+gateway+subnet+DDP port+4x
per-port pixel counts+reserved bytes+a 16-bit additive checksum. `$8000` is safely above the full 32KB P1 boot
image (every P1 `.eeprom` build pads to exactly 32768 bytes, confirmed earlier compiling `Main.spin` with `-e`),
stays inside the same 64KB I2C block as the boot image (no block-select addressing needed), and is page-aligned
(32768 = 128*256), so the whole block fits in one EEPROM page - one page-write, no page-split logic. A blank/
never-written EEPROM reads all `$FF`, fails the magic check immediately, and `Config.Load` falls straight through
to `LoadDefaults` (the same values that used to be Main.spin's fixed CON constants) - satisfies "still runs
correctly on missing/corrupt config" with no special-case code.

**Why a full reboot, not live reinitialization, after a config save**: confirmed by reading
`PixelDriver_E6804.spin`'s PASM that it reads `portTable`/`pinTable` from hub RAM exactly once at `entry`, never
again - so changing pixel counts live would need `pixels.Stop`/`Start` regardless, and would additionally leave
open whether changing W5200 socket 0's address registers while it's carrying live DDP traffic is safe (the
vendored driver's docs don't say, and there's no quick way to test it). A full `REBOOT` resets everything
(W5200, pixel driver, port table) to the same known-good state a normal power-up reaches.

**`REBOOT` verified by reading its compiled PASM output**, not just by trusting a web search: compiling a 3-line
test (`test/Reboot_Smoke_Test.spin`) shows FlexSpin's `REBOOT` keyword compiles to exactly the standard, documented
P1 software-reset technique - write the clock-mode byte to hub address `$0004` with the reset bit set (`#128`),
then execute the `clkset` PASM instruction, which forces an immediate hard reset re-reading the boot EEPROM. This
is the same mechanism as a real power cycle, not a hack - safe to rely on.

**Real hub-RAM numbers** (`flexspin --sizes`, P1 target): before this feature, `Main.spin` used 8112 of 32768
bytes. After adding `I2C_EEPROM.spin`/`Config.spin`/`HTTPServer.spin` and wiring them into `Main.spin` (including
the new `MAX_PIXELS_PER_PORT = 300` framebuffer, up from the old fixed 50/port), the full build is **23,496 of
32,768 bytes - 9,272 bytes free**. Comfortable margin; `MAX_PIXELS_PER_PORT = 300` doesn't need to come down.

**MAC/IP/gateway/subnet form fields are plain decimal octets (ip0..ip3 etc.) and 2-hex-digit MAC bytes (mac0..
mac5, no colons)** rather than single combined text fields - deliberately avoids needing any percent-decoding in
`HTTPServer.spin`, since digits and hex letters are never percent-encoded by a standard form submission, but a
colon (as in a conventional `02:00:00:00:00:01` MAC string) would be.

**Known accepted risk, not fixed**: `W5200_Driver.spin`'s `txTCP` has an internal `repeat until freespace > 0` loop
with no timeout. Not touched (it's vendored, working code) - low practical risk here since this feature's HTML
responses are small and sent immediately after accept, so the TX buffer essentially always has room.

**Found on real hardware (2026-10-02): I2C EEPROM read/write isn't working at all.** First real-hardware test
showed the config web page loading fine (W5200/HTTP path confirmed working) but displaying garbage IP/gateway/
subnet/pixel-count values on the very first-ever page load (no Save had been clicked). Traced systematically:
`test/Config_Load_Save_Test.spin` (fallback/roundtrip/corruption checks) failed, then the even more isolated
`test/I2C_EEPROM_Test.spin` (raw read/write roundtrip, no Config-level magic/checksum logic at all) ALSO failed -
narrowing the bug to `src/I2C_EEPROM.spin` itself, not `Config.spin`'s validation logic or the HTTP integration.
MAC and DDP port were also dropped from the configurable set per user decision (not needed) - `Config.spin`'s
block shrank from 42 to 34 bytes accordingly (see its header comment for the current field table).

Root cause not yet confirmed (no hardware access from this debugging session to test further), but a real,
plausible one was identified and fixed defensively: **`I2C_EEPROM.Start()` never forced the bus to a known-idle
state before the first transaction.** This board just booted FROM this same EEPROM over this same I2C bus (P28/
P29 are the Propeller's hard-wired boot pins, not board-configurable) - if the boot ROM's last transaction didn't
end perfectly cleanly, the EEPROM could be left mid-byte, waiting for more clock pulses, with SDA possibly stuck
low. Added a standard I2C bus-recovery sequence to `Start()` (clock SCL up to 9 times watching for SDA to release,
then force a clean STOP) before any real transaction - cheap, harmless even if this wasn't the actual cause.

`test/I2C_EEPROM_Test.spin` was also upgraded with granular LED-coded failure reporting (1 blink = WriteBlock
itself failed/never ACKed, 2 blinks = ReadBlock failed, 3 blinks = both succeeded but data didn't match) instead
of a single pass/fail pattern, specifically so the next hardware run narrows this down further without another
guess-and-reflash round-trip if the bus-recovery fix doesn't fully resolve it.

**Confirmed (2026-10-02): the I2C bus-recovery fix resolved it.** Re-ran `test/I2C_EEPROM_Test.spin` on real
hardware after adding the bus-recovery sequence to `I2C_EEPROM.Start()` - solid LED (PASS), write+read+data all
matched. Root cause is now reasonably confirmed as "EEPROM left mid-transaction after boot, needed a forced
recovery to idle before the first real transaction" rather than a logic bug in the read/write/ACK-check code
itself (that code was apparently correct all along).

**Found and fixed a second, separate bug (2026-10-02): the real cause of the original garbage-values symptom.**
After the I2C bus-recovery fix, re-running the upgraded (blink-coded) `test/Config_Load_Save_Test.spin` showed
check 1 (blank-EEPROM fallback) passing but check 2 (save/load roundtrip) failing - meaning Config's "is this
data invalid" path worked, but a real write-then-read-back roundtrip of its `word`-sized fields didn't. This is
exactly consistent with the risk flagged (but never actually verified) in the original plan: Config.spin's VAR
block mixed `long`/`word`/`byte` fields and assumed Spin1 packs them byte-tight with no alignment padding. Check 1
never actually exercised a real roundtrip of the word fields (it only confirms blank data is correctly rejected,
which only depends on the `long magic` field matching - trivially true regardless of any padding elsewhere), so it
couldn't have caught this. **Fixed by eliminating the assumption entirely**: `Config.spin` no longer uses a typed
VAR struct at all - it's one flat `byte block[34]` array with hand-computed offset constants (`OFS_IP`,
`OFS_PORT1`, etc.) and explicit `GetWord`/`SetWord`/`GetLong`/`SetLong` helpers that manually pack/unpack
multi-byte fields as big-endian byte pairs. A byte array has no ambiguity about per-element packing, so there's no
compiler behavior left to depend on. This is the actual root cause of the original "config page shows garbage on
first load" symptom - it was never really about the I2C bus-recovery issue (that was a real, separate bug, just
not THIS one) or about anything in the HTTP/buffer-sharing layer.

Lesson for next time: when a hand-written data-layout assumption is flagged as "not yet verified" (or similar) in
a plan, and the thing is non-trivial to verify quickly, treat it as a real risk worth structurally designing
around (e.g., a flat byte array from the start) rather than proceeding on the assumption and hoping a later test
catches it - in this case it took three separate rounds of hardware testing (full HTTP page, then two single-file
isolated tests) to actually localize.

**Confirmed (2026-10-02): the flat-byte-array fix resolved it.** Re-ran the updated `test/Config_Load_Save_Test.spin`
on real hardware - solid LED, all three checks (blank-fallback, save/load roundtrip, corrupted-checksum rejection)
passed. Both real bugs found during this feature's hardware bring-up (I2C bus-recovery, and the VAR-packing
assumption) are now fixed and confirmed at the layer each one lives in.

Note: `Config_Load_Save_Test.spin`'s check 3 deliberately leaves a corrupted checksum byte in the real EEPROM as
its last action (that's the point of the test) - so the NEXT thing flashed (`Main.spin`) will correctly see
"invalid" and boot from hardcoded defaults the first time, not because of a bug but because the test intentionally
left the stored config corrupted. Expected, not a regression.

**Still not yet done**: the full `Main.spin` GET/POST/reboot flow (load the config page, confirm it shows clean
defaults - 192.168.5.206 / gateway 192.168.5.1 / subnet 255.255.255.0 / 50-50-50-50 pixels - submit a change,
confirm it saves+reboots+persists). Given this project's own history of a false "it worked" report costing real
debugging time (see the WS2812 entries above), don't update README's status table to "Done" based on isolated
tests alone - confirm the full checklist in the plan file
(`C:\Users\scoot\.claude\plans\humble-leaping-hamster.md`) on real hardware first.

## Firmware update safety

Before flashing anything custom to a board's own EEPROM: back up the stock firmware first if possible (Propeller
Tool doesn't provide EEPROM readback by default the way it does write, so the safer path is to keep the *original
Propeller chip* as the backup — pull it, socket a spare P8X32A for all custom-firmware bring-up and testing, and
only move to the original board's own chip once the firmware is proven on the bench).
