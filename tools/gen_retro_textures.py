# Generates the retro texture set for the Sanatorium interior into
# res://textures/retro/. 128x128, 24-bit uncompressed TGA -- period-correct size,
# and small enough that nearest filtering reads as deliberate rather than cheap.
import math
import os
import random

OUT = r"x:/Vampire Game/vampire-game/textures/retro"
S = 128

os.makedirs(OUT, exist_ok=True)


def write_tga(name, px):
    hdr = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    hdr += S.to_bytes(2, "little") + S.to_bytes(2, "little")
    hdr += bytes([24, 32])            # 24bpp, top-left origin
    data = bytearray()
    for r, g, b in px:
        data += bytes((max(0, min(255, int(b))),
                       max(0, min(255, int(g))),
                       max(0, min(255, int(r)))))
    with open(os.path.join(OUT, name), "wb") as fh:
        fh.write(hdr + bytes(data))
    print("  ", name)


def vnoise(cells, rng):
    """Tileable value noise, returns a flat list of S*S floats in 0..1."""
    g = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [0.0] * (S * S)
    for y in range(S):
        fy = y / S * cells
        iy = int(fy) % cells
        jy = (iy + 1) % cells
        ty = fy - int(fy)
        ty = ty * ty * (3 - 2 * ty)
        for x in range(S):
            fx = x / S * cells
            ix = int(fx) % cells
            jx = (ix + 1) % cells
            tx = fx - int(fx)
            tx = tx * tx * (3 - 2 * tx)
            a = g[iy][ix] * (1 - tx) + g[iy][jx] * tx
            b = g[jy][ix] * (1 - tx) + g[jy][jx] * tx
            out[y * S + x] = a * (1 - ty) + b * ty
    return out


def fbm(rng, base_cells=4, octaves=3):
    acc = [0.0] * (S * S)
    amp, tot = 1.0, 0.0
    cells = base_cells
    for _ in range(octaves):
        n = vnoise(cells, rng)
        for i in range(S * S):
            acc[i] += n[i] * amp
        tot += amp
        amp *= 0.5
        cells *= 2
    return [v / tot for v in acc]


def blend(c, target, t):
    return (c[0] + (target[0] - c[0]) * t,
            c[1] + (target[1] - c[1]) * t,
            c[2] + (target[2] - c[2]) * t)


# ── Plaster: cream institutional wall, stained, peeling to brick ─────────────
def make_plaster():
    # Deliberately low-contrast. Anything bold in here tiles every couple of
    # metres and instantly reads as camouflage; the dramatic peeling is placed
    # by hand in the level as separate brick panels instead.
    rng = random.Random(1939)
    stain = fbm(rng, 4, 4)
    grit = vnoise(56, rng)
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            c = (196, 189, 173)
            c = blend(c, (166, 156, 138), max(0.0, stain[i] - 0.5) * 0.85)
            c = blend(c, (211, 206, 192), max(0.0, 0.44 - stain[i]) * 0.7)
            d = (grit[i] - 0.5) * 13
            px.append((c[0] + d, c[1] + d, c[2] + d))
    # Damp running down from the ceiling line, and a few hairline cracks.
    for _ in range(11):
        cx = rng.randrange(S)
        w = rng.choice((1, 1, 2))
        length = rng.randrange(S // 3, S)
        for y in range(length):
            f = (1.0 - y / length) * 0.22
            for k in range(w):
                i = y * S + (cx + k) % S
                px[i] = blend(px[i], (150, 140, 122), f)
    for _ in range(5):
        x, y = rng.randrange(S), rng.randrange(S)
        ang = rng.uniform(0, math.tau)
        for _ in range(rng.randrange(25, 70)):
            ang += rng.uniform(-0.4, 0.4)
            x = (x + math.cos(ang)) % S
            y = (y + math.sin(ang)) % S
            i = int(y) * S + int(x)
            px[i] = blend(px[i], (142, 133, 118), 0.55)
    write_tga("plaster.tga", px)


# ── Dado: the painted lower band, scuffed down to plaster at the edges ───────
def make_dado():
    # Same rule as the plaster: keep it quiet. An earlier pass had big
    # high-contrast paint chips and at 2m tiling the corridor came out looking
    # like camouflage netting. Chips are now small, sparse and low-contrast.
    rng = random.Random(4711)
    stain = fbm(rng, 4, 4)
    grit = vnoise(60, rng)
    chip = fbm(rng, 16, 2)
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            c = (74, 106, 102)
            c = blend(c, (56, 80, 78), max(0.0, stain[i] - 0.5) * 1.0)
            c = blend(c, (92, 124, 118), max(0.0, 0.44 - stain[i]) * 0.8)
            d = (grit[i] - 0.5) * 14
            c = (c[0] + d, c[1] + d, c[2] + d)
            if chip[i] > 0.865:
                c = blend(c, (150, 146, 132), min(1.0, (chip[i] - 0.865) / 0.05) * 0.8)
            # Grime pooling along the skirting.
            if y > S * 0.86:
                c = blend(c, (44, 52, 50), (y - S * 0.86) / (S * 0.14) * 0.45)
            px.append(c)
    # Trolley scuffs -- the marks a hospital corridor actually collects.
    for _ in range(14):
        y0 = rng.randrange(int(S * 0.2), int(S * 0.8))
        x0 = rng.randrange(S)
        ln = rng.randrange(8, 40)
        for k in range(ln):
            i = y0 * S + (x0 + k) % S
            px[i] = blend(px[i], (104, 130, 124), 0.4)
    write_tga("dado.tga", px)


# ── Brick: what is behind the plaster ───────────────────────────────────────
def make_brick():
    rng = random.Random(1042)
    grit = vnoise(40, rng)
    bw, bh, mortar = 32, 16, 3
    px = []
    tone = {}
    for y in range(S):
        for x in range(S):
            row = y // bh
            off = (bw // 2) if row % 2 else 0
            bx = ((x + off) % S) // bw
            key = (row, bx)
            if key not in tone:
                tone[key] = (rng.uniform(-18, 18), rng.uniform(-8, 8), rng.uniform(-8, 8))
            iny = y % bh
            inx = (x + off) % bw
            i = y * S + x
            if iny < mortar or inx < mortar:
                c = (164, 158, 146)
                c = blend(c, (120, 114, 104), grit[i] * 0.5)
            else:
                t = tone[key]
                c = (132 + t[0], 84 + t[1], 70 + t[2])
                d = (grit[i] - 0.5) * 26
                c = (c[0] + d, c[1] + d, c[2] + d)
            px.append(c)
    # Soot and damp over the whole face -- fresh brickwork behind failed plaster
    # would read as a repair, not a ruin.
    grime = fbm(rng, 4, 3)
    for i in range(S * S):
        px[i] = blend(px[i], (86, 78, 70), max(0.0, grime[i] - 0.38) * 0.9)
    write_tga("brick.tga", px)


# ── Floor: worn terrazzo, the grid you see down every one of these corridors ─
def make_floor():
    rng = random.Random(777)
    dirt = fbm(rng, 3, 3)
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            inx, iny = x % 64, y % 64
            if inx < 3 or iny < 3:
                c = (58, 58, 55)
            else:
                c = (124, 126, 117)
                r = rng.random()
                if r < 0.055:
                    c = (168, 170, 160)     # aggregate fleck
                elif r < 0.10:
                    c = (86, 88, 82)
            c = blend(c, (62, 60, 54), max(0.0, dirt[i] - 0.42) * 1.3)
            px.append(c)
    write_tga("floor.tga", px)


# ── Ceiling: damp-stained, cracked ──────────────────────────────────────────
def make_ceiling():
    rng = random.Random(313)
    stain = fbm(rng, 4, 3)
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            c = (172, 168, 158)
            s = stain[i]
            if s > 0.52:
                c = blend(c, (146, 124, 96), min(1.0, (s - 0.52) * 2.6))
            c = blend(c, (196, 193, 184), max(0.0, 0.4 - s))
            px.append(c)
    for _ in range(6):                       # cracks
        x, y = rng.randrange(S), rng.randrange(S)
        ang = rng.uniform(0, math.tau)
        for _ in range(rng.randrange(30, 90)):
            ang += rng.uniform(-0.35, 0.35)
            x = (x + math.cos(ang)) % S
            y = (y + math.sin(ang)) % S
            i = int(y) * S + int(x)
            px[i] = blend(px[i], (104, 99, 90), 0.75)
    write_tga("ceiling.tga", px)


# ── Wood: door leaves, frames, fallen boards ────────────────────────────────
def make_wood():
    rng = random.Random(88)
    warp = vnoise(6, rng)
    grit = vnoise(64, rng)
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            g = math.sin((x * 0.55) + warp[i] * 6.0) * 0.5 + 0.5
            c = blend((104, 74, 50), (68, 45, 29), g * 0.7)
            d = (grit[i] - 0.5) * 16
            c = (c[0] + d, c[1] + d, c[2] + d)
            if x % 32 < 2:                   # plank seams
                c = blend(c, (40, 26, 17), 0.7)
            px.append(c)
    write_tga("wood.tga", px)


# ── Rusted metal: bed frames, rails, pipework ───────────────────────────────
def make_metal():
    rng = random.Random(555)
    rust = fbm(rng, 5, 3)
    grit = vnoise(52, rng)
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            c = (136, 138, 134)
            c = blend(c, (142, 80, 42), max(0.0, rust[i] - 0.46) * 1.9)
            c = blend(c, (86, 52, 30), max(0.0, rust[i] - 0.70) * 2.0)
            d = (grit[i] - 0.5) * 20
            px.append((c[0] + d, c[1] + d, c[2] + d))
    write_tga("metal.tga", px)


# ── Rubble: fallen plaster and masonry ──────────────────────────────────────
def make_rubble():
    rng = random.Random(9001)
    chunk = vnoise(18, rng)
    grit = vnoise(64, rng)
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            c = blend((146, 140, 128), (92, 86, 76), chunk[i])
            if chunk[i] > 0.72:
                c = blend(c, (150, 96, 76), 0.35)     # broken brick in the pile
            d = (grit[i] - 0.5) * 30
            px.append((c[0] + d, c[1] + d, c[2] + d))
    write_tga("rubble.tga", px)


print("writing retro texture set ->", OUT)
make_plaster()
make_dado()
make_brick()
make_floor()
make_ceiling()
make_wood()
make_metal()
make_rubble()
print("done")
