"""Generate the addon's own UI textures (original art, MIT like the rest of the repo).

Usage:
    python pipeline/gen_ui_textures.py

Writes into AnimalitosPlanner/Media/:
    round-fill.tga   white rounded rectangle, used 9-sliced as a panel fill
    round-edge.tga   1px white rounded outline, used 9-sliced as a panel border
    round-mask.tga   white rounded rectangle (2:1), used as a mask for artwork

All are 32-bit uncompressed TGA (what WoW loads reliably), anti-aliased by
supersampling. Pure Python, no dependencies.
"""
import struct
from pathlib import Path

MEDIA = Path(__file__).resolve().parent.parent / "AnimalitosPlanner" / "Media"
SS = 4  # supersampling per axis


def inside_round_rect(x, y, w, h, r):
    """True if point (x, y) is inside a w*h rectangle with corner radius r."""
    if x < 0 or y < 0 or x > w or y > h:
        return False
    cx = min(max(x, r), w - r)
    cy = min(max(y, r), h - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def coverage(px, py, test):
    hits = 0
    for sy in range(SS):
        for sx in range(SS):
            if test(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS):
                hits += 1
    return hits / (SS * SS)


def write_tga(path, w, h, alpha_at):
    out = bytearray()
    for y in range(h - 1, -1, -1):  # TGA origin: bottom-left
        for x in range(w):
            a = round(255 * alpha_at(x, y))
            out += bytes((255, 255, 255, a))  # BGRA, white
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    path.write_bytes(header + out)
    print(f"wrote {path.name} ({w}x{h})")


def main():
    MEDIA.mkdir(parents=True, exist_ok=True)
    size, radius, stroke = 32, 7.0, 1.0

    def fill(x, y):
        return coverage(x, y, lambda u, v: inside_round_rect(u, v, size, size, radius))

    def edge(x, y):
        def ring(u, v):
            outer = inside_round_rect(u, v, size, size, radius)
            inner = inside_round_rect(u - stroke, v - stroke, size - 2 * stroke, size - 2 * stroke, radius - stroke)
            return outer and not inner
        return coverage(x, y, ring)

    mw, mh, mr = 128, 64, 10.0

    def mask(x, y):
        return coverage(x, y, lambda u, v: inside_round_rect(u, v, mw, mh, mr))

    write_tga(MEDIA / "round-fill.tga", size, size, fill)
    write_tga(MEDIA / "round-edge.tga", size, size, edge)
    write_tga(MEDIA / "round-mask.tga", mw, mh, mask)


if __name__ == "__main__":
    main()
