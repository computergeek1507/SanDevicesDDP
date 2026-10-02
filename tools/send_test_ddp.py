#!/usr/bin/env python3
"""
send_test_ddp.py - sends a single hand-crafted DDP packet to a SanDevicesDDP board, for bring-up testing.

Usage:
    python send_test_ddp.py [host] [r] [g] [b] [pixel_count]

Defaults: host=192.168.5.206, color=red (255,0,0), pixel_count=10

Sends one DDP frame (PUSH flag set, type RGB8, offset 0) filling the first `pixel_count` pixels of whatever port
owns channel offset 0 (port J1 / "port 0" in Main.spin's port table) with the given color. On the board, this
should make the green activity LED toggle once (confirms DDP_Parser.ProcessPacket() accepted the frame) and, if
the pixel driver and wiring are also working, light up that many pixels on J1 in the given color.

This does not depend on xLights or any other sequencing software - just Python's standard library socket module.
"""
import socket
import sys

DDP_PORT = 4048
FLAG_PUSH = 0x01
TYPE_RGB8 = 0x01


def build_ddp_packet(offset: int, data: bytes) -> bytes:
    header = bytes([
        0x40 | FLAG_PUSH,      # flags: version 01, PUSH set
        0,                     # sequence (disabled)
        TYPE_RGB8,             # data type
        1,                     # destination/output ID (unused by this firmware)
        (offset >> 24) & 0xFF, (offset >> 16) & 0xFF, (offset >> 8) & 0xFF, offset & 0xFF,
        (len(data) >> 8) & 0xFF, len(data) & 0xFF,
    ])
    return header + data


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "192.168.5.206"
    r = int(sys.argv[2]) if len(sys.argv) > 2 else 255
    g = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    b = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    pixel_count = int(sys.argv[5]) if len(sys.argv) > 5 else 10

    data = bytes([r, g, b]) * pixel_count
    packet = build_ddp_packet(0, data)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(packet, (host, DDP_PORT))
    sock.close()

    print(f"Sent {len(packet)}-byte DDP packet to {host}:{DDP_PORT} "
          f"({pixel_count} pixels of RGB({r},{g},{b}) at offset 0)")


if __name__ == "__main__":
    main()
