"""Convert a PNG into the addon icon (square TGA, 32-bit, power-of-two size).

Usage:
    python3 pipeline/png2tga.py <image.png> [AnimalitosPlanner/Media/icon.tga] [size=128]

WoW loads uncompressed TGA textures reliably; the size must be a power of two.
Pure Python (no Pillow). Non-square images are stretched to a square.
The generated icon.tga is git-ignored (local-only art); see CLAUDE.md.
"""
import struct
import sys
import zlib
from pathlib import Path


def read_png(path):
    d = Path(path).read_bytes()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    pos, idat = 8, b""
    while pos < len(d):
        ln, typ = struct.unpack(">I4s", d[pos:pos + 8])
        body = d[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat += body
        pos += 12 + ln
    if bd != 8 or ct not in (2, 6) or il != 0:
        raise SystemExit("only 8-bit RGB/RGBA non-interlaced PNGs are supported")
    bpp = 4 if ct == 6 else 3
    raw, stride = zlib.decompress(idat), w * bpp
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        f, line = raw[p], bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            line = bytearray((a + b) & 255 for a, b in zip(line, prev))
        elif f == 3:
            for i in range(stride):
                line[i] = (line[i] + ((line[i - bpp] if i >= bpp else 0) + prev[i]) // 2) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b, c = prev[i], (prev[i - bpp] if i >= bpp else 0)
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else str(Path(__file__).resolve().parent.parent / "AnimalitosPlanner" / "Media" / "icon.tga")
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 128
    if size & (size - 1):
        raise SystemExit("size must be a power of two (64, 128, 256)")
    w, h, bpp, rows = read_png(src)
    out = bytearray()
    for oy in range(size - 1, -1, -1):  # TGA origin: bottom-left
        y0, y1 = oy * h // size, (oy + 1) * h // size
        for ox in range(size):
            x0, x1 = ox * w // size, (ox + 1) * w // size
            acc, n = [0, 0, 0, 0], 0
            for y in range(y0, max(y1, y0 + 1), 2):
                r = rows[y]
                for x in range(x0, max(x1, x0 + 1), 2):
                    i = x * bpp
                    acc[0] += r[i]; acc[1] += r[i + 1]; acc[2] += r[i + 2]
                    acc[3] += r[i + 3] if bpp == 4 else 255
                    n += 1
            R, G, B, A = (v // n for v in acc)
            out += bytes((B, G, R, A))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    Path(dst).parent.mkdir(parents=True, exist_ok=True)
    Path(dst).write_bytes(header + out)
    print(f"{src} ({w}x{h}) -> {dst} ({size}x{size})")


if __name__ == "__main__":
    main()
