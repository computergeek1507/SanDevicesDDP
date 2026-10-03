{{
  Config_Load_Save_Test.spin

  Toolchain/wiring sanity check - NOT part of the real firmware, no W5200/DDP/networking involved. Exercises
  Config.spin's Load/Save/validation logic directly against real EEPROM hardware:

    1. Writes an all-$FF ("blank EEPROM") pattern over the config block, confirms Load reports invalid and falls
       back to the same defaults LoadDefaults sets.
    2. Sets distinctive non-default values, Saves, scribbles the in-RAM copy back to defaults (so a pass can't be
       a false positive from stale RAM), Loads, confirms the saved values come back exactly.
    3. Directly corrupts the stored checksum byte (via a separate I2C_EEPROM instance, bypassing Config on
       purpose), confirms Load rejects it and falls back to defaults rather than loading corrupted data.

  LED-coded result on the green status LED (P16) - distinct pattern per failing check, so a failing run says WHERE
  without another hardware round-trip:
    solid ON               = PASS - all three checks passed
    1 blink, pause, repeat = check 1 failed (blank EEPROM didn't correctly fall back to defaults)
    2 blinks, pause, repeat = check 2 failed (save/load roundtrip didn't return the saved values)
    3 blinks, pause, repeat = check 3 failed (corrupted checksum wasn't rejected)
}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  LED_PIN     = 16
  SCL_PIN     = 28
  SDA_PIN     = 29
  EEPROM_ADDR = $50
  CFG_OFFSET  = 32768
  BLOCK_SIZE  = 34           ' must match Config.spin's current BLOCK_SIZE (MAC/DDP port removed - not configurable)

OBJ
  config : "../src/Config"
  i2c    : "../src/I2C_EEPROM"  ' separate instance, used only here to directly poke/corrupt bytes for test setup -
                                 ' see docs/NOTES.md on why a second plain-Spin (non-cog) instance is safe to use
                                 ' alongside Config's own internal one

VAR
  byte blankBuf[BLOCK_SIZE]

PUB Main | valid, failedCheck

  dira[LED_PIN]~~
  outa[LED_PIN]~

  config.Start(SCL_PIN, SDA_PIN)
  i2c.Start(SCL_PIN, SDA_PIN)

  failedCheck := 0

  ' --- 1: blank/invalid EEPROM falls back to defaults ---
  bytefill(@blankBuf, $FF, BLOCK_SIZE)
  i2c.WriteBlock(EEPROM_ADDR, CFG_OFFSET, @blankBuf, BLOCK_SIZE)

  valid := config.Load
  if valid or config.GetPort1Pixels <> 50
    failedCheck := 1

  ' --- 2: full save/load roundtrip with distinctive non-default values ---
  if failedCheck == 0
    config.SetPort1Pixels(123)
    config.SetIP(10, 20, 30, 40)
    config.Save

    config.LoadDefaults                      ' scribble the in-RAM copy so a pass can't be a stale-RAM false positive
    valid := config.Load
    if not valid or config.GetPort1Pixels <> 123
      failedCheck := 2

  ' --- 3: a corrupted checksum byte is rejected, not silently loaded ---
  if failedCheck == 0
    CorruptChecksumByte
    valid := config.Load
    if valid or config.GetPort1Pixels <> 50   ' back to defaults, not the corrupted-but-still-123 value
      failedCheck := 3

  if failedCheck == 0
    outa[LED_PIN]~~
    repeat
  else
    repeat
      repeat valid from 1 to failedCheck      ' reusing 'valid' as a loop counter here, its own value no longer needed
        outa[LED_PIN]~~
        waitcnt(clkfreq / 4 + cnt)
        outa[LED_PIN]~
        waitcnt(clkfreq / 4 + cnt)
      waitcnt(clkfreq + cnt)                  ' pause between blink groups

PRI CorruptChecksumByte | b
  i2c.ReadBlock(EEPROM_ADDR, CFG_OFFSET + (BLOCK_SIZE - 2), @b, 1)   ' checksum is the last 2 bytes of the block
  b := (b + 1) & $FF
  i2c.WriteBlock(EEPROM_ADDR, CFG_OFFSET + (BLOCK_SIZE - 2), @b, 1)
