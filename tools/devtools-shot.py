#!/usr/bin/env python3
"""Ask a Chromium page to screenshot itself, over the DevTools protocol.

No websocket library needed: the exchange is one upgrade, one text frame out, and frames back
until a complete JSON message arrives.

    tools/devtools-shot.py <ws-url> <output.png> [method]
"""

import base64
import json
import os
import socket
import struct
import sys
import urllib.parse


def connect(url: str) -> socket.socket:
    parts = urllib.parse.urlsplit(url)
    host, port = parts.hostname, parts.port or 80
    path = parts.path + ("?" + parts.query if parts.query else "")
    sock = socket.create_connection((host, port), timeout=30)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall(
        f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\n"
        f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode()
    )
    # Read headers; anything after them already belongs to the stream.
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise SystemExit("connection closed during the handshake")
        buf += chunk
    head, _, rest = buf.partition(b"\r\n\r\n")
    if b"101" not in head.split(b"\r\n")[0]:
        raise SystemExit(head.decode(errors="replace"))
    sock.settimeout(30)
    return _Framed(sock, rest)


class _Framed:
    """A socket with the leftover bytes of the handshake already read."""

    def __init__(self, sock: socket.socket, buffered: bytes):
        self.sock = sock
        self.buffer = buffered

    def recv_exact(self, n: int) -> bytes:
        while len(self.buffer) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("closed")
            self.buffer += chunk
        out, self.buffer = self.buffer[:n], self.buffer[n:]
        return out


def send_text(conn: _Framed, message: str) -> None:
    payload = message.encode()
    header = bytearray([0x81])  # FIN + text
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length < 1 << 16:
        header.append(0x80 | 126)
        header += struct.pack(">H", length)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", length)
    mask = os.urandom(4)
    header += mask
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    conn.sock.sendall(bytes(header) + masked)


def read_message(conn: _Framed) -> str:
    while True:
        first = conn.recv_exact(2)
        opcode = first[0] & 0x0F
        masked = first[1] & 0x80
        length = first[1] & 0x7F
        if length == 126:
            length = struct.unpack(">H", conn.recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", conn.recv_exact(8))[0]
        mask = conn.recv_exact(4) if masked else None
        payload = conn.recv_exact(length)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode == 0x8:
            raise EOFError("the page closed the connection")
        if opcode in (0x1, 0x2):
            return payload.decode(errors="replace")
        # ping, pong, continuation: keep reading


def main() -> None:
    url = sys.argv[1]
    output = sys.argv[2]
    method = sys.argv[3] if len(sys.argv) > 3 else "Page.captureScreenshot"

    conn = connect(url)
    arguments = {"format": "png"} if method.endswith("captureScreenshot") else {}
    send_text(conn, json.dumps({"id": 1, "method": method, "params": arguments}))

    for _ in range(50):
        message = json.loads(read_message(conn))
        if message.get("id") != 1:
            continue
        if "error" in message:
            raise SystemExit(f"DevTools said: {message['error']}")
        data = message["result"].get("data")
        if not data:
            print(json.dumps(message["result"])[:400])
            return
        with open(output, "wb") as handle:
            handle.write(base64.b64decode(data))
        print(f"wrote {output} ({os.path.getsize(output)} bytes)")
        return
    raise SystemExit("no reply")


if __name__ == "__main__":
    main()
