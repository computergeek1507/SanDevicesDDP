# Provenance

Vendored unmodified from the official Parallax community library mirror:

- Source: https://github.com/parallaxinc/propeller/blob/master/libraries/community/p1/All/Wiznet%20W5200%20Driver/W5200_Driver.spin
- Original OBEX listing: https://obex.parallax.com/obex/wiznet-w5200-driver/
- Author: Benjamin Yaroch (W5200 adaptation), based on Timothy D. Swieter's W5100_SPI_Driver.spin; additional revisions by Jim St. John
- Version: 1.3 (per in-file header), modified April 17, 2016
- Retrieved: 2026-09-30, via `gh api` against the `parallaxinc/propeller` GitHub repo (the OBEX site itself only offers a zip download, which wasn't fetchable as text from this environment)

Copied byte-for-byte into `src/W5200_Driver.spin` for use in this project (same file, not re-encoded or edited).
If SanDevices' board turns out to need changes (e.g. the /INT pin being unused is already consistent with what
we traced on the E6804 - see `docs/pin_mapping_E6804.md` - so no changes were needed there), make them in
`src/W5200_Driver.spin` directly and note the divergence here.

## API used by this project

- `start(_scs, _sclk, _mosi, _miso, _reset) : okay` - launches the driver's cog, pins passed by number
- `InitAddresses(_block, _macPTR, _gatewayPTR, _subnetPTR, _ipPTR)` - one-shot network config
- `SocketOpen(_socket, _mode, _srcPort, _destPort, _destIP)` with `_mode = _UDPPROTO` - opens a UDP socket
- `rxUDP(_socket, _dataPtr) : bytesRead` - pulls one received UDP packet into a hub RAM buffer. Returns 0 if
  nothing received. When non-zero, the buffer layout is: bytes 0-3 source IP, bytes 4-5 source port, bytes 6-7
  payload size (big-endian), byte 8 onward = the actual payload (the DDP packet, in our case) - so
  `DDP_Parser.ProcessPacket()` gets called with `dataPtr + 8` and `bytesRead - 8`.

/INT is not used by this driver version at all (socket status is polled via SPI reads), which matches the E6804
board's INT pin turning out not to be wired to the Propeller - no driver changes needed for that.
