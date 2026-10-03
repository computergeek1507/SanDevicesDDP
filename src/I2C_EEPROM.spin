{{
  I2C_EEPROM.spin

  Minimal bit-banged I2C driver for the board's boot EEPROM (Atmel AT24C1024BPU or ON Semi 24M01, both standard
  24xx-series parts - see docs/NOTES.md), used by Config.spin to persist settings above the Propeller's own 32KB
  boot image. Pins are the Propeller's default I2C boot pins, SCL=P28/SDA=P29 (docs/pin_mapping_E6804.md confirms
  this board doesn't deviate from default).

  Deliberately plain Spin, not PASM: unlike PixelDriver_E6804.spin's WS2812 timing (tight deadlines on BOTH ends)
  or W5200_Driver.spin's SPI (hardware-clocked), I2C to a 24xx EEPROM only has MINIMUM timing (SCL low >= 4.7us,
  high >= 4.0us for standard mode) and no upper bound - the master fully controls the clock, so running slower is
  always safe. This only runs at boot (Config.Load) and on an explicit web-page Save, never in a hot loop, so the
  simplicity of a plain waitcnt-delimited bit-bang loop is worth more here than PASM's speed.

  Open-drain-safe idiom throughout: outa is set low once at Start and never changed again - "driving low" means
  setting dira to output (dira=1, outa already 0), "releasing" means setting dira to input (dira=0, pulled high by
  the pull-ups the boot EEPROM already requires to function, so they're already present on this board).
}}

CON
  ' ~6.25us at 80MHz (12.5ns/cycle) - comfortable margin over the 4.0-4.7us standard-mode minimums, covering
  ' both possible EEPROM vendors on this board (AT24C1024 vs 24M01, jumper-selected per docs/NOTES.md).
  I2C_DELAY_CYC = 500

  WRITE_POLL_LIMIT = 2000      ' generous bound on ACK-poll retries after a write, so a dead/missing EEPROM
                                ' returns false instead of hanging forever

VAR
  long sclPin, sdaPin

PUB Start(_sclPin, _sdaPin) | i
'' Call once before any ReadBlock/WriteBlock. Leaves both lines released (idle-high).
  sclPin := _sclPin
  sdaPin := _sdaPin
  outa[sclPin]~
  outa[sdaPin]~
  dira[sclPin]~
  dira[sdaPin]~

  ' Bus recovery: this board just booted FROM this same EEPROM over this same I2C bus - if the boot ROM's last
  ' transaction didn't end cleanly (e.g. reset mid-byte), the EEPROM could be stuck waiting for more clocks with
  ' SDA held low. Standard recovery: clock SCL up to 9 times (enough to finish any stuck byte+ACK) while watching
  ' SDA release, then force a clean STOP - cheap insurance, harmless even if the bus was already idle.
  repeat i from 0 to 8
    if ina[sdaPin] == 1
      quit
    sclRelease
    sclLow
  i2cStop

PUB ReadBlock(devAddr, wordAddr, bufPtr, numBytes) : ok | i
'' Standard 24xx "sequential read": write the 16-bit word address, repeated-start, then clock numBytes out,
'' ACKing all but the last byte (NACK + Stop on the last, per the I2C/24xx protocol).
  i2cStart
  if not i2cWriteByte((devAddr << 1) | 0)
    i2cStop
    return false
  i2cWriteByte((wordAddr >> 8) & $FF)
  i2cWriteByte(wordAddr & $FF)
  i2cStart
  if not i2cWriteByte((devAddr << 1) | 1)
    i2cStop
    return false
  repeat i from 0 to numBytes - 1
    byte[bufPtr][i] := i2cReadByte(i < (numBytes - 1))
  i2cStop
  ok := true

PUB WriteBlock(devAddr, wordAddr, bufPtr, numBytes) : ok | i, retries
'' Standard 24xx page write (block must fit in one page - caller's responsibility), then ACK-polls for the
'' EEPROM's internal write-cycle completion instead of a fixed delay - vendor-timing-agnostic by construction,
'' which matters since this board may have either of two EEPROM parts with different write-cycle times.
  i2cStart
  i2cWriteByte((devAddr << 1) | 0)
  i2cWriteByte((wordAddr >> 8) & $FF)
  i2cWriteByte(wordAddr & $FF)
  repeat i from 0 to numBytes - 1
    i2cWriteByte(byte[bufPtr][i])
  i2cStop

  retries := 0
  repeat
    i2cStart
    ok := i2cWriteByte((devAddr << 1) | 0)
    i2cStop
    retries++
  until ok or retries > WRITE_POLL_LIMIT

  return ok

PRI sclRelease
  dira[sclPin]~
  waitcnt(cnt + I2C_DELAY_CYC)

PRI sclLow
  dira[sclPin]~~
  waitcnt(cnt + I2C_DELAY_CYC)

PRI sdaRelease
  dira[sdaPin]~

PRI sdaLow
  dira[sdaPin]~~

PRI i2cStart
  sdaRelease
  sclRelease
  sdaLow
  waitcnt(cnt + I2C_DELAY_CYC)
  sclLow

PRI i2cStop
  sdaLow
  sclRelease
  waitcnt(cnt + I2C_DELAY_CYC)
  sdaRelease
  waitcnt(cnt + I2C_DELAY_CYC)

PRI i2cWriteByte(b) : ack | i
  repeat i from 7 to 0
    if (b >> i) & 1
      sdaRelease
    else
      sdaLow
    sclRelease
    sclLow
  sdaRelease                    ' release SDA so the slave can drive the ACK bit
  sclRelease
  ack := (ina[sdaPin] == 0)     ' ACK = slave pulled SDA low
  sclLow

PRI i2cReadByte(sendAck) : b | i
  sdaRelease                    ' release so the slave can drive each data bit
  repeat 8
    sclRelease
    b := (b << 1) | ina[sdaPin]
    sclLow
  if sendAck
    sdaLow
  else
    sdaRelease
  sclRelease
  sclLow
  sdaRelease
