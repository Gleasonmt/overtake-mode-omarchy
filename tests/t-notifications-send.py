#!/usr/bin/env python3
"""Send one notification over the session bus, for the real-Quickshell test.

notify-send can't hand over raw image pixels, so this speaks D-Bus itself
(standard library only). It uses DBUS_SESSION_BUS_ADDRESS, which the test points
at a private bus.

  t-notifications-send.py [--app NAME] [--summary TEXT] [--body TEXT | --body-file PATH]
                          [--image-path PATH]
                          [--image-data WIDTHxHEIGHT] [--lie-size N] [--count N]
                          [--hold]

--image-data sends a picture of that size in the `image-data` hint, 4 bytes a
pixel; with --lie-size, that many bytes whatever the size says. --count sends
that many. --hold stays connected until killed.
"""
import argparse, os, socket, struct, sys


class Writer:
    def __init__(self):
        self.b = bytearray()

    def align(self, n):
        self.b += b"\0" * (-len(self.b) % n)

    def y(self, v):
        self.b.append(v)

    def b32(self, v):
        self.align(4)
        self.b += struct.pack("<I", 1 if v else 0)

    def i(self, v):
        self.align(4)
        self.b += struct.pack("<i", v)

    def u(self, v):
        self.align(4)
        self.b += struct.pack("<I", v)

    def s(self, v):
        raw = v.encode()
        self.u(len(raw))
        self.b += raw + b"\0"

    def g(self, v):
        raw = v.encode()
        self.y(len(raw))
        self.b += raw + b"\0"


def message(serial, member, dest, path, iface, signature, body):
    fields = Writer()

    def field(code, sig, write):
        fields.align(8)
        fields.y(code)
        fields.g(sig)
        write(fields)

    field(1, "o", lambda w: w.s(path))
    field(2, "s", lambda w: w.s(iface))
    field(3, "s", lambda w: w.s(member))
    field(6, "s", lambda w: w.s(dest))
    if signature:
        field(8, "g", lambda w: w.g(signature))
    head = struct.pack("<cBBBII", b"l", 1, 0, 1, len(body), serial)
    out = bytearray(head + struct.pack("<I", len(fields.b)) + bytes(fields.b))
    out += b"\0" * (-len(out) % 8)
    return bytes(out) + bytes(body)


class Bus:
    def __init__(self):
        addr = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        spec = dict(p.split("=", 1) for p in addr.split(":", 1)[1].split(",") if "=" in p)
        self.sock = socket.socket(socket.AF_UNIX)
        path = spec.get("path")
        self.sock.connect(path if path else "\0" + spec["abstract"])
        self.sock.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
        if not self.sock.recv(4096).startswith(b"OK"):
            sys.exit("bus refused the connection")
        self.sock.sendall(b"BEGIN\r\n")
        self.serial = 0
        self.call("Hello", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "", b"")

    def read(self, n):
        data = bytearray()
        while len(data) < n:
            part = self.sock.recv(min(1 << 20, n - len(data)))
            if not part:
                sys.exit("bus closed the connection")
            data += part
        return bytes(data)

    def call(self, member, dest, path, iface, signature, body):
        self.serial += 1
        self.sock.sendall(message(self.serial, member, dest, path, iface, signature, body))
        while True:
            head = self.read(16)
            kind = head[1]
            size, _, flen = struct.unpack("<III", head[4:16])
            rest = self.read(flen + (-(16 + flen) % 8) + size)
            if kind == 2:
                return rest[-size:] if size else b""
            if kind == 3:
                sys.exit("error reply: " + repr(rest[:300]))


def notify(bus, args):
    w = Writer()
    w.s(args.app)
    w.u(0)
    w.s("")
    w.s(args.summary)
    w.s(args.body)
    w.u(0)           # the actions' length, filled in below
    acts_at = len(w.b) - 4
    for i in range(args.actions):
        w.s(str(i))
        w.s("x")
    struct.pack_into("<I", w.b, acts_at, len(w.b) - acts_at - 4)
    hints = Writer()
    hints.b = w.b    # (same buffer: alignment counts from the start of the body)
    w.u(0)
    length_at = len(w.b) - 4
    w.align(8)
    start = len(w.b)
    if args.hint_size:
        w.align(8)
        w.s("x-big")
        w.g("s")
        w.s("x" * args.hint_size)
    if args.image_path:
        w.align(8)
        w.s("image-path")
        w.g("s")
        w.s(args.image_path)
    if args.image_data:
        width, height = (int(x) for x in args.image_data.split("x"))
        size = width * height * 4 if args.lie_size < 0 else args.lie_size
        w.align(8)
        w.s("image-data")
        w.g("(iiibiiay)")
        w.align(8)
        w.i(width)
        w.i(height)
        w.i(width * 4)
        w.b32(True)
        w.i(8)
        w.i(4)
        w.u(size)
        w.b += bytes(size)
    struct.pack_into("<I", w.b, length_at, len(w.b) - start)
    w.i(-1)
    reply = bus.call("Notify", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                     "org.freedesktop.Notifications", "susssasa{sv}i", w.b)
    return struct.unpack("<I", reply[:4])[0]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--app", default="Test")
    p.add_argument("--summary", default="Test")
    p.add_argument("--body", default="")
    p.add_argument("--body-file", default="")   # (a marker stays out of this program's own arguments)
    p.add_argument("--image-path", default="")
    p.add_argument("--image-data", default="")
    p.add_argument("--lie-size", type=int, default=-1)   # claim that size, send this many bytes
    p.add_argument("--count", type=int, default=1)
    p.add_argument("--hint-size", type=int, default=0)   # a string hint of that length
    p.add_argument("--actions", type=int, default=0)     # that many buttons
    p.add_argument("--hold", action="store_true")
    args = p.parse_args()
    if args.body_file:
        args.body = open(args.body_file).read()
    bus = Bus()
    for _ in range(args.count):
        print(notify(bus, args))
    sys.stdout.flush()
    if args.hold:
        bus.sock.recv(1)


main()
