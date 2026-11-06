"""Generate the addon's own UI textures (original art, MIT like the rest of the repo).

Usage:
    python pipeline/gen_ui_textures.py

Writes into AnimalitosPlanner/Media/:
    round-fill.tga   white rounded rectangle, used 9-sliced as a panel fill
    round-edge.tga   1px white rounded outline, used 9-sliced as a panel border
    round-mask.tga   white rounded rectangle (2:1), used as a mask for artwork
    nav-*.tga        flat sidebar glyphs (home, farm, collection, settings)

All are 32-bit uncompressed TGA (what WoW loads reliably), anti-aliased by
supersampling. Pure Python, no dependencies.
"""
import math
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

    # Sidebar glyphs: flat white silhouettes, tinted in game.
    for name, test in NAV_ICONS.items():
        write_tga(MEDIA / f"nav-{name}.tga", ICON, ICON,
                  lambda x, y, t=test: coverage(x, y, t))


# ---------------------------------------------------------------------------
# Sidebar icons (64x64, y grows downward)
# ---------------------------------------------------------------------------
ICON = 64


def in_poly(x, y, pts):
    """Even-odd point-in-polygon test."""
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def in_rect(x, y, x0, y0, x1, y1):
    return x0 <= x <= x1 and y0 <= y <= y1


def in_circle(x, y, cx, cy, r):
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def home(x, y):
    roof = in_poly(x, y, [(32, 5), (3, 31), (61, 31)])
    walls = in_rect(x, y, 12, 29, 52, 58)
    door = in_rect(x, y, 27, 40, 37, 58)
    return (roof or walls) and not door


def horseshoe(x, y):
    cx, cy, ro, ri = 32, 28, 24, 13
    arch = y <= cy and in_circle(x, y, cx, cy, ro) and not in_circle(x, y, cx, cy, ri)
    legs = in_rect(x, y, cx - ro, cy, cx - ri, 52) or in_rect(x, y, cx + ri, cy, cx + ro, 52)
    heels = in_rect(x, y, cx - ro - 2, 50, cx - ri + 1, 57) or in_rect(x, y, cx + ri - 1, 50, cx + ro + 2, 57)
    holes = [(14, 20), (22, 10), (42, 10), (50, 20), (13.5, 36), (50.5, 36)]
    if any(in_circle(x, y, hx, hy, 2.4) for hx, hy in holes):
        return False
    return arch or legs or heels


def book(x, y):
    left = in_poly(x, y, [(4, 12), (30, 17), (30, 56), (4, 51)])
    right = in_poly(x, y, [(34, 17), (60, 12), (60, 51), (34, 56)])
    return left or right


def gear(x, y):
    cx, cy = 32, 32
    dx, dy = x - cx, y - cy
    d = math.hypot(dx, dy)
    if d < 9:
        return False  # center hole
    phase = (math.atan2(dy, dx) / (2 * math.pi) * 8) % 1.0
    tooth = 0.18 < phase < 0.62
    return d <= (28 if tooth else 21)


NAV_ICONS = {"home": home, "farm": horseshoe, "collection": book, "settings": gear}


if __name__ == "__main__":
    main()
