# E682 Pin Mapping (16-port board)

Status: **NOT YET TRACED.** Fill in the tables below, then the firmware config tables in
`../src/PixelDriver_E682.spin` and `../src/W5200_Driver.spin` get generated from this file, not the other way
around — don't hardcode pin numbers anywhere else.

## Tracing procedure

Do this with the board **unpowered** and the Propeller chip **removed from its socket** (IC3, the only socketed
part that faces left). Use a multimeter in continuity/beep mode.

1. **Pixel outputs (through the 74HCT541/158 chain).** For each of the 16 output connectors (J1-J16), the signal
   path is: Propeller socket pin -> 74HCT541 buffer (IC5-8) input pin -> 74HCT541 output pin -> possibly a
   74HCT158 mux (IC9-12) -> 270-ohm resistor network (RN1-2 .. RN15-16) -> output connector pin. You don't need to
   understand every intermediate hop — just beep from each empty socket pin (1-40, skipping ones you can rule out
   like power/ground/crystal) to each of the 16 connectors' data pins, and note which socket pin lights up which
   connector. It's faster to start from the connector side (16 known points) and probe toward the socket (40
   candidates) than the reverse.
2. **W5200 SPI signals.** The WIZ820IO module plugs into two 6-pin SIP sockets, J23 and J24 (12 pins total). With
   the WIZ820IO module also removed, beep from each of those 12 socket pins back to the Propeller socket pins.
   You're looking for 6 signals: MOSI, MISO, SCLK, CS/SS (chip select), RST (reset), INT (interrupt) — the WIZ820IO
   module's own pinout (silkscreened on the module, or in its datasheet) tells you which of the 12 pins is which
   signal; you just need where each lands on the Propeller.
3. **PROGRAM port (J20).** This is very likely a standard Prop Plug pinout already (VDD 3.3V / RX / TX / VSS in
   Parallax's usual order — SanDevices' own doc says the Vss pin is marked on the silkscreen). Confirm by reading
   the silkscreen next to J20 rather than tracing, and note it below — this is what plugging in a Prop Plug relies
   on being right before you risk anything.
4. Also note the boot EEPROM's I2C pins if they're not the Propeller's usual default (P28=SCL, P29=SDA) — check
   for any jumper or non-default wiring, since Rev 1.3 boards have a jumper (J26) affecting EEPROM compatibility
   but that's a timing/vendor selector, not a pin remap, so this is likely a non-issue but worth a 30-second check.

## Results

### Board revision
- [ ] Rev 1.0 / 1.1 / 1.3 (check silkscreen lower-left corner): _____

### Pixel output ports (P0-P31 -> connector)

| Propeller Pin | Output Connector (J#) | Notes |
|---|---|---|
| P? | J1 | |
| P? | J2 | |
| P? | J3 | |
| P? | J4 | |
| P? | J5 | |
| P? | J6 | |
| P? | J7 | |
| P? | J8 | |
| P? | J9 | |
| P? | J10 | |
| P? | J11 | |
| P? | J12 | |
| P? | J13 | |
| P? | J14 | |
| P? | J15 | |
| P? | J16 | |

### Status LEDs

SanDevices' assembly manual lists 5 LEDs (1 Green, 1 Red, 3 Yellow), but per the actual board only Red and Green
are populated/relevant here.

| Propeller Pin | LED | Notes |
|---|---|---|
| P? | Red | |
| P? | Green | |

### W5200 / WIZ820IO SPI

| Signal | Propeller Pin |
|---|---|
| MOSI | P? |
| MISO | P? |
| SCLK | P? |
| CS/SS | P? |
| RST | P? |
| INT | P? |

### PROGRAM port (J20) — 4 pins, left to right as viewed on silkscreen

| Pin # | Signal |
|---|---|
| 1 | |
| 2 | |
| 3 | |
| 4 | |

### Boot EEPROM I2C (only fill in if different from Propeller default P28=SCL/P29=SDA)

| Signal | Propeller Pin |
|---|---|
| SCL | |
| SDA | |
