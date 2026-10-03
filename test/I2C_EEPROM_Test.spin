{{
  I2C_EEPROM_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware, no W5200/DDP/networking involved at all. Bit-bangs
  P28/P29 directly via I2C_EEPROM.spin to write a known pattern to EEPROM offset $8000 (the same offset
  Config.spin uses for its persistent settings block) and read it back, specifically exercising the write-then-
  ACK-poll completion logic with no artificial delay inserted by this test - that's the one piece of custom timing
  logic in the whole Config/I2C feature.

  LED-coded result on the green status LED (P16, per docs/pin_mapping_E6804.md) - distinct patterns per failure
  point, so a failing run tells us WHERE it failed without needing extra hardware debugging round-trips:
    solid ON               = PASS - write, read, and data all matched
    1 blink, pause, repeat = WriteBlock itself returned false (EEPROM never ACKed the write or write-cycle poll)
    2 blinks, pause, repeat = ReadBlock itself returned false (EEPROM never ACKed the read request)
    3 blinks, pause, repeat = both calls returned true, but the read-back data didn't match what was written
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  LED_PIN     = 16
  SCL_PIN     = 28
  SDA_PIN     = 29
  EEPROM_ADDR = $50
  TEST_OFFSET = $8000
  TEST_LEN    = 16

OBJ
  i2c : "../src/I2C_EEPROM"

VAR
  byte writeBuf[TEST_LEN]
  byte readBuf[TEST_LEN]

PUB Main | i, writeOk, readOk, mismatch, blinkCount

  dira[LED_PIN]~~
  outa[LED_PIN]~

  i2c.Start(SCL_PIN, SDA_PIN)

  repeat i from 0 to TEST_LEN - 1
    writeBuf[i] := (i * 17 + 5) & $FF            ' arbitrary non-trivial pattern, not all-zero/all-FF

  writeOk := i2c.WriteBlock(EEPROM_ADDR, TEST_OFFSET, @writeBuf, TEST_LEN)

  readOk := false
  mismatch := false
  if writeOk
    bytefill(@readBuf, 0, TEST_LEN)
    readOk := i2c.ReadBlock(EEPROM_ADDR, TEST_OFFSET, @readBuf, TEST_LEN)
    if readOk
      repeat i from 0 to TEST_LEN - 1
        if readBuf[i] <> writeBuf[i]
          mismatch := true

  if writeOk and readOk and not mismatch
    outa[LED_PIN]~~
    repeat
  else
    if not writeOk
      blinkCount := 1
    elseif not readOk
      blinkCount := 2
    else
      blinkCount := 3

    repeat
      repeat i from 1 to blinkCount
        outa[LED_PIN]~~
        waitcnt(clkfreq / 4 + cnt)
        outa[LED_PIN]~
        waitcnt(clkfreq / 4 + cnt)
      waitcnt(clkfreq + cnt)                      ' pause between blink groups
