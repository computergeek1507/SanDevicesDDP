{{
  DDP_Parser.spin

  Parses incoming DDP (Distributed Display Protocol) UDP packets into a shared hub-RAM pixel frame buffer.
  Hardware-independent: owns no pins, no SPI, no cog of its own. Call ProcessPacket() with a pointer to a
  received UDP payload (from W5200_Driver.spin's UDP receive path, once that exists) and its length.

  DDP header (10 bytes, all multi-byte fields big-endian):
    byte 0    flags: bit0=PUSH bit1=QUERY bit2=REPLY bit3=STORAGE bit4=TIMECODE bit6-7=VERSION(01)
    byte 1    sequence number (0 = disabled, else wraps 1-15) - not currently checked
    byte 2    data type - this firmware only accepts TYPE_RGB8, everything else is dropped
    byte 3    destination/output ID - ignored (single logical device, one flat channel space)
    byte 4-7  data offset: absolute BYTE offset into this device's logical channel space
    byte 8-9  data length in bytes
    [payload, `length` bytes, follows]

  Addressing model (ported from the algorithm in C:\software\ESP32P4Pix\main\ddp.c, cross-checked against
  C:\software\ddp_viewer\lib\services\ddp_receiver.dart and C:\software\xLights_hinks\xLights\outputs\DDPOutput.cpp):
  the whole controller's outputs are one flat logical byte-address space. Each physical port owns a contiguous
  sub-range of that space, described by a (startChannel, numBytes) pair in the port table passed to Start().
  A single DDP packet can span or overlap more than one port's range (e.g. a sender doing one big packet across
  several universes/ports), so ProcessPacket walks the port table and does an interval-overlap copy into each
  port's slice of the frame buffer rather than assuming one packet maps to exactly one port.

  NOT YET COMPILED - no Propeller toolchain available in this environment. Verify with Propeller Tool
  (Plan Step 1) before relying on this; Spin1 syntax was hand-checked but not built.
}}

CON
  DDP_PORT        = 4048
  DDP_HDR_LEN     = 10
  DDP_MAX_PAYLOAD = 1440                         ' typical DDP sender chunk size (xLights, ESP32P4Pix use this)

  ' byte 0 flag bits
  FLAG_PUSH       = %00000001
  FLAG_QUERY      = %00000010
  FLAG_REPLY      = %00000100
  FLAG_STORAGE    = %00001000
  FLAG_TIMECODE   = %00010000

  TYPE_RGB8       = $01                          ' only data type this firmware accepts; others are dropped

VAR
  long  framebufferPtr                           ' hub address of the shared pixel frame buffer (bytes)
  long  portTablePtr                             ' hub address of numPorts x (long startChannel, long numBytes)
  long  numPorts                                 ' 16 for E682, 4 for E6804
  long  pktCount                                 ' accepted-packet counter, readable for a status page

PUB Start(fbPtr, ptPtr, ports)
'' fbPtr - hub address of the byte array holding all ports' pixel data, contiguous, indexed by absolute channel
'' ptPtr - hub address of the port table: `ports` pairs of (startChannel, numBytes) longs, in the same port
''         order PixelDriver_E682.spin / PixelDriver_E6804.spin expects
'' ports - number of ports in the table
  framebufferPtr := fbPtr
  portTablePtr := ptPtr
  numPorts := ports
  pktCount := 0

PUB PacketCount
  return pktCount

PUB ProcessPacket(pktPtr, pktLen) : accepted | offset, dlen, dataPtr, pktAbs0, pktAbs1, portIdx, portStart, portLen, portAbs0, portAbs1, ov0, ov1, copyLen, pktOff, portOff
'' Call with a pointer to a raw received UDP payload and its length in bytes.
'' Returns true if it was a valid pushed RGB8 DDP frame that got applied to the frame buffer.
  accepted := false

  if pktLen < DDP_HDR_LEN
    return
  if not (byte[pktPtr][0] & FLAG_PUSH)
    return
  if byte[pktPtr][2] <> TYPE_RGB8
    return

  offset := (byte[pktPtr][4] << 24) | (byte[pktPtr][5] << 16) | (byte[pktPtr][6] << 8) | byte[pktPtr][7]
  dlen   := (byte[pktPtr][8] << 8) | byte[pktPtr][9]
  if (DDP_HDR_LEN + dlen) > pktLen
    dlen := pktLen - DDP_HDR_LEN

  dataPtr := pktPtr + DDP_HDR_LEN
  pktAbs0 := offset
  pktAbs1 := offset + dlen - 1

  repeat portIdx from 0 to numPorts - 1
    portStart := long[portTablePtr][portIdx * 2]
    portLen   := long[portTablePtr][portIdx * 2 + 1]
    if portLen > 0
      portAbs0 := portStart
      portAbs1 := portStart + portLen - 1
      ov0 := portAbs0 #> pktAbs0                 ' #> = max
      ov1 := portAbs1 <# pktAbs1                 ' <# = min
      if ov0 =< ov1
        copyLen := ov1 - ov0 + 1
        pktOff  := ov0 - pktAbs0
        portOff := ov0 - portAbs0
        bytemove(framebufferPtr + portStart + portOff, dataPtr + pktOff, copyLen)

  pktCount++
  accepted := true
