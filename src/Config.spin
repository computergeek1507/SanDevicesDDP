{{
  Config.spin

  EEPROM-backed persistent configuration: network settings (IP/gateway/subnet) and per-port pixel counts. MAC and
  the DDP listen port are NOT configurable (per user decision - stay fixed, set directly in Main.spin).

  Stored as one flat byte array with explicit offset constants below - deliberately NOT a typed VAR struct
  (long/word/byte fields mixed together). An earlier version used a typed struct on the assumption that Spin1
  packs VAR fields byte-tight with no alignment padding; that assumption was never actually verified and real
  hardware testing caught a real bug consistent with it being wrong (save/load roundtrip test failed specifically
  on the word-sized per-port pixel-count fields, while the byte-only "is this blank/invalid" path worked fine - see
  docs/NOTES.md). A flat byte array with hand-computed offsets removes the ambiguity entirely: byte arrays are
  unambiguously one byte per element, so there's no compiler packing behavior to depend on.

  Stored at EEPROM byte offset $8000 (32768) on the same boot EEPROM the Propeller already uses to boot itself
  (I2C pins SCL=P28/SDA=P29, standard device address - see docs/pin_mapping_E6804.md) - that offset is safely
  above the full 32KB P1 boot image (confirmed by compiling to .eeprom format, which always pads to exactly 32768
  bytes), stays inside the same 64KB I2C addressing block as the boot image (no block-select bit needed), and is
  page-aligned (32768 = 128*256), so the whole block fits in a single EEPROM page.

  Field layout (byte offsets into `block`):
    0   long  magic         $53444450 ("SDDP")
    4   byte  version       1
    5   byte  ip[4]
    9   byte  gateway[4]
    13  byte  subnet[4]
    17  word  port1Pixels   (big-endian: high byte first)
    19  word  port2Pixels
    21  word  port3Pixels
    23  word  port4Pixels
    25  byte  reserved[7]
    32  word  checksum      16-bit additive sum of bytes 0..31

  A blank/never-written EEPROM reads all $FF, which fails the magic check immediately and falls straight through
  to LoadDefaults - satisfying "still runs correctly on missing/corrupt config" with no special-case code.
}}

OBJ
  i2c : "I2C_EEPROM"

CON
  CFG_MAGIC    = $53444450
  CFG_VERSION  = 1
  CFG_OFFSET   = 32768
  EEPROM_ADDR  = $50          ' 7-bit device address (standard 24xx default, A2/A1/B0 all 0 - boot already
                               ' proves this is correct, since the Propeller's own boot ROM uses the same address)

  MAX_PIXELS_PER_PORT = 300   ' see docs/NOTES.md for the hub-RAM budget this is based on

  ' byte offsets into `block` - see field layout table above
  OFS_MAGIC    = 0
  OFS_VERSION  = 4
  OFS_IP       = 5
  OFS_GATEWAY  = 9
  OFS_SUBNET   = 13
  OFS_PORT1    = 17
  OFS_PORT2    = 19
  OFS_PORT3    = 21
  OFS_PORT4    = 23
  OFS_RESERVED = 25
  OFS_CHECKSUM = 32
  BLOCK_SIZE   = 34

VAR
  byte block[BLOCK_SIZE]

PUB Start(sclPin, sdaPin)
  i2c.Start(sclPin, sdaPin)

PUB Load : valid
'' Reads the block from EEPROM. If magic/version/checksum don't all check out, fills in the hardcoded defaults
'' instead (same values Main.spin's CON block used to have) and returns false - either way the caller always
'' gets a usable config back, so Main.spin needs no fallback logic of its own.
  i2c.ReadBlock(EEPROM_ADDR, CFG_OFFSET, @block, BLOCK_SIZE)
  if GetLong(OFS_MAGIC) == CFG_MAGIC and block[OFS_VERSION] == CFG_VERSION and GetWord(OFS_CHECKSUM) == computeChecksum
    valid := true
  else
    LoadDefaults
    valid := false

PUB LoadDefaults
'' The same values that used to be fixed CON constants directly in Main.spin.
  SetLong(OFS_MAGIC, CFG_MAGIC)
  block[OFS_VERSION] := CFG_VERSION

  block[OFS_IP+0] := 192
  block[OFS_IP+1] := 168
  block[OFS_IP+2] := 5
  block[OFS_IP+3] := 206

  block[OFS_GATEWAY+0] := 192
  block[OFS_GATEWAY+1] := 168
  block[OFS_GATEWAY+2] := 5
  block[OFS_GATEWAY+3] := 1

  block[OFS_SUBNET+0] := 255
  block[OFS_SUBNET+1] := 255
  block[OFS_SUBNET+2] := 255
  block[OFS_SUBNET+3] := 0

  SetWord(OFS_PORT1, 50)
  SetWord(OFS_PORT2, 50)
  SetWord(OFS_PORT3, 50)
  SetWord(OFS_PORT4, 50)

  bytefill(@block[OFS_RESERVED], 0, 7)

  SetWord(OFS_CHECKSUM, computeChecksum)

PUB Save : ok
  SetWord(OFS_CHECKSUM, computeChecksum)
  ok := i2c.WriteBlock(EEPROM_ADDR, CFG_OFFSET, @block, BLOCK_SIZE)

PUB GetBlockPtr
  return @block

' --- getters: Main.spin has no direct access to another object's VAR fields in Spin1, only its PUB methods, so
' these are how it reads current config - the byte-array fields return pointers, reusable directly as the
' pointer arguments W5200_Driver's address methods and HTTPServer's page-building methods already expect ---

PUB GetIPPtr
  return @block[OFS_IP]

PUB GetGatewayPtr
  return @block[OFS_GATEWAY]

PUB GetSubnetPtr
  return @block[OFS_SUBNET]

PUB GetPort1Pixels
  return GetWord(OFS_PORT1)

PUB GetPort2Pixels
  return GetWord(OFS_PORT2)

PUB GetPort3Pixels
  return GetWord(OFS_PORT3)

PUB GetPort4Pixels
  return GetWord(OFS_PORT4)

' --- validating setters: the only way external callers (HTTPServer, via Main.spin) are allowed to touch fields,
' so bad/out-of-range form input can never reach the shared struct un-clamped ---

PUB SetIP(a, b, c, d)
  block[OFS_IP+0] := (0 #> a) <# 255
  block[OFS_IP+1] := (0 #> b) <# 255
  block[OFS_IP+2] := (0 #> c) <# 255
  block[OFS_IP+3] := (0 #> d) <# 255

PUB SetGateway(a, b, c, d)
  block[OFS_GATEWAY+0] := (0 #> a) <# 255
  block[OFS_GATEWAY+1] := (0 #> b) <# 255
  block[OFS_GATEWAY+2] := (0 #> c) <# 255
  block[OFS_GATEWAY+3] := (0 #> d) <# 255

PUB SetSubnet(a, b, c, d)
  block[OFS_SUBNET+0] := (0 #> a) <# 255
  block[OFS_SUBNET+1] := (0 #> b) <# 255
  block[OFS_SUBNET+2] := (0 #> c) <# 255
  block[OFS_SUBNET+3] := (0 #> d) <# 255

PUB SetPort1Pixels(n)
  SetWord(OFS_PORT1, (0 #> n) <# MAX_PIXELS_PER_PORT)

PUB SetPort2Pixels(n)
  SetWord(OFS_PORT2, (0 #> n) <# MAX_PIXELS_PER_PORT)

PUB SetPort3Pixels(n)
  SetWord(OFS_PORT3, (0 #> n) <# MAX_PIXELS_PER_PORT)

PUB SetPort4Pixels(n)
  SetWord(OFS_PORT4, (0 #> n) <# MAX_PIXELS_PER_PORT)

PRI GetLong(ofs) : v
  v := (block[ofs] << 24) | (block[ofs+1] << 16) | (block[ofs+2] << 8) | block[ofs+3]

PRI SetLong(ofs, v)
  block[ofs+0] := (v >> 24) & $FF
  block[ofs+1] := (v >> 16) & $FF
  block[ofs+2] := (v >> 8) & $FF
  block[ofs+3] := v & $FF

PRI GetWord(ofs) : v
  v := (block[ofs] << 8) | block[ofs+1]

PRI SetWord(ofs, v)
  block[ofs+0] := (v >> 8) & $FF
  block[ofs+1] := v & $FF

PRI computeChecksum : sum | i
  sum := 0
  repeat i from 0 to OFS_CHECKSUM - 1    ' everything before the 2-byte checksum field itself
    sum += block[i]
  sum &= $FFFF
