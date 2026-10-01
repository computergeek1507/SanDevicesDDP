# E6804 Pin Mapping (4-port board)

Status: **TRACED.** Pixel outputs, LEDs, EEPROM, PROGRAM port, and W5200 SPI all confirmed (INT is simply not
wired up on this board — the driver will poll socket status registers instead of using interrupt-driven receive).
Same core architecture as the E682 (same Propeller, same WIZ820IO module, same
74HCT541/158 buffer family) on a smaller/cheaper PCB with only 4 output ports instead of 16. Do **not** assume the
E682's pin mapping applies here — trace this board separately, since SanDevices could easily have laid out the
smaller PCB with different pin assignments even with identical ICs. See `pin_mapping_E682.md` for the full
step-by-step tracing procedure (identical process, just 4 output connectors instead of 16 and correspondingly
fewer 74HCT541/158/resistor-network parts populated).

## Results

### Board revision
- [1.3 ] Rev ___ (check silkscreen lower-left corner)

### Pixel data output port pins (P0-P31 -> connector)

| Propeller Pin | Output Connector (J#) | Notes |
|---|---|---|
| P0 | J1 | |
| P4 | J2 | |
| P8 | J3 | |
| P12 | J4 | |

### Pixel clock ports pins (P0-P31 -> connector)

| Propeller Pin | Output Connector (J#) | Notes |
|---|---|---|
| P21 | J1 | |
| P22 | J2 | |
| P20 | J3 | |
| P19 | J4 | |

### Status LEDs

E6804 has 2 status LEDs (fewer than the E682's 5 - no per-cluster yellow indicators on this smaller board).

| Propeller Pin | LED | Notes |
|---|---|---|
| P17 | Red | |
| P16 | Green | |

### W5200 / WIZ820IO SPI

| Signal | Propeller Pin |
|---|---|
| MOSI | P24 |
| MISO | P23 |
| SCLK | P27 |
| CS/SS | P26 |
| RST | P25 |
| INT | not connected — W5200 driver must poll socket status registers, not use interrupt-driven receive |

### PROGRAM port (J20) — 4 pins, left to right as viewed on silkscreen

| Pin # | Signal |
|---|---|
| 1 | GND |
| 2 | RESn |
| 3 | P31 |
| 4 | P30 |

### Boot EEPROM I2C (only fill in if different from Propeller default P28=SCL/P29=SDA)

| Signal | Propeller Pin |
|---|---|
| SCL |P28 |
| SDA |P29 |
