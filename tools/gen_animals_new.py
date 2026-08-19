"""Generates the PS1-style low-poly rigged animal family for Parnitha.

Everything is built mathematically from this one file -- vertices, UVs, an
armature, skin weights and three baked animations (idle / walk / death) -- so
the whole bestiary can be regenerated at will.  Nothing here touches the
existing sheep2 / deer2 models; every output is suffixed `_new`.

    models/animals/<name>_new.gltf         self-contained glTF 2.0 (embedded buffer)
    textures/animals/<name>_atlas_new.png  128x128 atlas, 15-bit colour, no AA

The full pipeline, in order -- step 2 is easy to forget and Godot will happily
build the previous model from its import cache if you do (tools/build_animals_new.gd
checks the bounds against the manifest and refuses, rather than doing it quietly):

    1. python tools/gen_animals_new.py                  geometry, atlases, clips
    2. re-import res://models/animals + res://textures/animals in the editor
       (or: godot --headless --path . --import)
    3. godot --headless --path . --script res://tools/build_animals_new.gd
    4. python tools/verify_animals_new.py               glTF/atlas structure
       godot --headless --path . --script res://tools/verify_scenes_new.gd
       godot --headless --path . --script res://tests/test_animals_new.gd
"""

import json
import math
import os
import random
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ps1_model import *                                          # noqa: F401,F403

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(ROOT, "models", "animals")
TEX_DIR = os.path.join(ROOT, "textures", "animals")


# ─────────────────────────────────────────────────────────────────────────────

#  Atlas
# ─────────────────────────────────────────────────────────────────────────────

# Named sub-rects of the sheet, in pixels: (x, y, w, h)
REGIONS = {
    "body":  (0, 0, 64, 64),
    "belly": (64, 0, 32, 32),
    "head":  (96, 0, 32, 32),
    "face":  (64, 32, 32, 32),
    "snout": (96, 32, 32, 32),
    "leg":   (0, 64, 32, 32),
    "hoof":  (32, 64, 32, 32),
    "horn":  (64, 64, 32, 32),
    "eye":   (96, 64, 32, 32),
    "tail":  (0, 96, 32, 32),
    "ear":   (32, 96, 32, 32),
    "back":  (64, 96, 64, 32),
}


def cell_noise(a, b, seed):
    """Deterministic 0..1 per integer cell. Cheap stand-in for a hash-based
    value noise -- enough to break up a lattice without a gradient field."""
    h = (a * 374761393 + b * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def q15(v):
    """Clamp to 0..255 and quantise to 5 bits per channel -- PS1 framebuffers
    were 15-bit, and the banding is half the look."""
    return max(0, min(255, int(v))) & 0xF8


class Atlas:
    def __init__(self, seed):
        self.px = bytearray(TEX * TEX * 3)
        self.rng = random.Random(seed)

    def _put(self, x, y, r, g, b):
        i = (y * TEX + x) * 3
        self.px[i] = q15(r)
        self.px[i + 1] = q15(g)
        self.px[i + 2] = q15(b)

    def fill(self, region, color, style="fur", accent=None, amount=14):
        x0, y0, w, h = REGIONS[region]
        r0, g0, b0 = color
        ar, ag, ab = accent if accent else (r0, g0, b0)
        rng = self.rng
        for y in range(h):
            for x in range(w):
                n = rng.uniform(-amount, amount)
                r, g, b = r0 + n, g0 + n, b0 + n

                if style == "fur":
                    # coarse vertical bristle streaks
                    if (x + (y // 4)) % 5 == 0:
                        r, g, b = r * 0.86, g * 0.86, b * 0.86
                elif style == "wool":
                    # Fleece clumps. Rows are offset like brickwork and each
                    # clump gets its own brightness, or a straight lattice
                    # reads as graph paper at this texel density.
                    row = y // 4
                    ox = x + (row % 2) * 2
                    k = 0.95 + 0.11 * cell_noise(ox // 4, row, 7)
                    fx = (ox % 4) - 1.5
                    fy = (y % 4) - 1.5
                    k *= 1.03 - 0.030 * (abs(fx) + abs(fy))
                    r, g, b = r * k, g * k, b * k
                elif style == "flat":
                    pass
                elif style == "hide":
                    # broad mottling from two out-of-step cell sizes, so no
                    # plaid emerges the way crossed sine waves would give
                    k = 0.93 + 0.14 * (0.6 * cell_noise(x // 6, y // 7, 3)
                                       + 0.4 * cell_noise(x // 11, y // 9, 11))
                    r, g, b = r * k, g * k, b * k
                elif style == "gloss":
                    # bone / horn: bright at the tip (top of the tile)
                    k = 1.18 - 0.5 * (y / max(1, h - 1))
                    r, g, b = r * k, g * k, b * k

                # every tile darkens toward its lower edge so the flat-shaded
                # facets pick up a cheap baked-in gradient
                shade = 1.0 - 0.18 * (y / max(1, h - 1))
                self._put(x0 + x, y0 + y, r * shade, g * shade, b * shade)

        if accent and style in ("fur", "hide", "wool"):
            self.speckle(region, accent)

    def speckle(self, region, color, count=None, size=2):
        """Scattered blocky patches -- fawn spots, piglet stripes' softening."""
        x0, y0, w, h = REGIONS[region]
        rng = self.rng
        for _ in range(count if count is not None else (w * h) // 60):
            sx = rng.randrange(0, max(1, w - size))
            sy = rng.randrange(0, max(1, h - size))
            for y in range(size):
                for x in range(size):
                    self._put(x0 + sx + x, y0 + sy + y, *color)

    def stripes(self, region, color, period=7, width=2):
        """Piglet livery: crisp longitudinal bands."""
        x0, y0, w, h = REGIONS[region]
        for y in range(h):
            if (y % period) < width:
                for x in range(w):
                    i = ((y0 + y) * TEX + x0 + x) * 3
                    self.px[i] = q15(color[0])
                    self.px[i + 1] = q15(color[1])
                    self.px[i + 2] = q15(color[2])

    def paint_eye(self, region, sclera, pupil, cx=0.5, cy=0.34,
                  rx=0.13, ry=0.105):
        """Paint an eye straight into a face tile.

        Geometry eyes kept ending up buried inside the skull, and a separate
        eye quad has to be re-tuned every time the head changes shape. Painted
        into the face tile it lands on both cheeks by construction, costs no
        triangles, and cannot sink. `cx` stays at 0.5 because the two head
        sides map the tile in opposite directions -- anything off-centre would
        put the left eye further forward than the right.
        """
        x0, y0, w, h = REGIONS[region]
        for y in range(h):
            for x in range(w):
                dx = (x + 0.5 - cx * w) / (rx * w)
                dy = (y + 0.5 - cy * h) / (ry * h)
                d = dx * dx + dy * dy
                if d > 2.10:
                    continue
                if d > 1.0:
                    # dark socket, which is what carries the eye at
                    # the distance the player actually sees these
                    i = ((y0 + y) * TEX + x0 + x) * 3
                    self.px[i] = q15(self.px[i] * 0.55)
                    self.px[i + 1] = q15(self.px[i + 1] * 0.55)
                    self.px[i + 2] = q15(self.px[i + 2] * 0.55)
                elif d <= 0.42:
                    self._put(x0 + x, y0 + y, *pupil)
                else:
                    self._put(x0 + x, y0 + y, *sclera)
        # wet highlight: one blocky glint, upper-left of the pupil
        gx = int((cx - rx * 0.32) * w)
        gy = int((cy - ry * 0.34) * h)
        for y in range(max(0, gy), min(h, gy + 1)):
            for x in range(max(0, gx), min(w, gx + 1)):
                self._put(x0 + x, y0 + y, 236, 232, 224)

    def eye(self, region, sclera, pupil):
        """One eye tile, used by both face sides."""
        x0, y0, w, h = REGIONS[region]
        for y in range(h):
            for x in range(w):
                self._put(x0 + x, y0 + y, *sclera)
        for y in range(h // 2 - 5, h // 2 + 5):
            for x in range(w // 2 - 6, w // 2 + 6):
                self._put(x0 + x, y0 + y, *pupil)
        # single specular pixel block -- reads as wet eye at PS1 resolution
        for y in range(h // 2 - 4, h // 2 - 1):
            for x in range(w // 2 - 4, w // 2 - 1):
                self._put(x0 + x, y0 + y, 230, 230, 230)

    def save(self, path):
        write_png(path, TEX, TEX, self.px)


def uv_rect(region, inset=0.5):
    """Region -> (u0, v0, u1, v1) with a half-texel inset so nearest sampling
    never bleeds a neighbouring tile along a seam."""
    x, y, w, h = REGIONS[region]
    return ((x + inset) / TEX, (y + inset) / TEX,
            (x + w - inset) / TEX, (y + h - inset) / TEX)


# ─────────────────────────────────────────────────────────────────────────────

#  Quadruped construction
#
#  Body stations are written as (z, y, half_width, half_height).  The animal
#  faces -Z, +Y is up, +X is its right.  Vertical prisms get a local frame of
#  r = +X, u = +Z, so their `half` reads as (half_width, half_depth).
# ─────────────────────────────────────────────────────────────────────────────

def station(t):
    """(z, y, hw, hh) -> (centre, half)"""
    return (0.0, t[1], t[0]), (t[2], t[3])


BODY_FACES = faces("body", side_u="back", side_d="belly")
HEAD_FACES = faces("head", side_p="face", side_n="face", cap_b="snout")
# The muzzle front becomes the nose pad. "hoof" is the near-black tile every
# species already carries, so this costs no atlas space.
SNOUT_FACES = faces("snout", cap_b="hoof")
LEG_FACES = faces("leg", cap_b="hoof")
HOOF_FACES = faces("hoof")


def build_animal(cfg):
    """Returns (mesh, rig).  Shared skeleton and body plan for every species;
    the per-species `extras` hook bolts on tusks, antlers, horns and fleece."""
    mesh, rig = Mesh(uv_rect), Rig()
    torso = cfg["torso"]
    legs = cfg["legs"]

    rear_c, _ = station(torso[0])
    chest_c, _ = station(torso[-1])
    neck_a, _ = station(cfg["neck"][0])
    neck_b, _ = station(cfg["neck"][1])
    head_a, _ = station(cfg["head"][0])

    rig.add("root", None, (0.0, 0.0, 0.0))
    rig.add("spine", "root", rear_c)
    rig.add("chest", "spine", chest_c)
    rig.add("neck", "chest", neck_a)
    rig.add("head", "neck", neck_b)
    rig.add("tail", "spine", cfg["tail"][0])

    fx, fz = legs["front"]
    bx, bz = legs["back"]
    for side, sx in (("l", 1.0), ("r", -1.0)):
        rig.add("leg_f%s_upper" % side, "chest", (sx * fx, legs["shoulder_y"], fz))
        rig.add("leg_f%s_lower" % side, "leg_f%s_upper" % side,
                (sx * fx, legs["knee_f_y"], fz))
        rig.add("leg_b%s_upper" % side, "spine", (sx * bx, legs["hip_y"], bz))
        rig.add("leg_b%s_lower" % side, "leg_b%s_upper" % side,
                (sx * bx, legs["knee_b_y"], bz))

    b = {n: rig.idx(n) for n in rig.names}

    # ── torso: one lofted tube, weights ramping rear-to-front ──────────────
    w_torso = blend_along(rear_c, chest_c,
                          [b["spine"], b["spine"], b["chest"], b["chest"]])
    torso_rings = [station(t) for t in torso]
    mesh.add_tube(torso_rings, [BODY_FACES] * (len(torso_rings) - 1), w_torso,
                  cap_a="body", cap_b="body")

    # ── neck and head: a single tube from the shoulders to the muzzle. Split
    #    at the midpoint so a ring of vertices sits on the neck bone and can
    #    bend with it.
    (na, nh0), (nb, nh1) = station(cfg["neck"][0]), station(cfg["neck"][1])
    nm = v_mul(v_add(na, nb), 0.5)
    nmh = ((nh0[0] + nh1[0]) * 0.5, (nh0[1] + nh1[1]) * 0.5)
    w_neck = blend_along(na, nb, [b["chest"], b["neck"], b["head"]])
    neck_faces = faces("body", side_u="back", side_d="belly")
    (ha, hh0), (hb, hh1) = station(cfg["head"][0]), station(cfg["head"][1])

    def w_neck_head(p):
        # the head half of the chain rides the skull outright
        return rigid(b["head"])(p) if p[2] <= ha[2] else w_neck(p)

    mesh.add_tube([(na, nh0), (nm, nmh), (nb, nh1), (hb, hh1)],
                  [neck_faces, neck_faces, HEAD_FACES], w_neck_head,
                  cap_a="body", cap_b="snout")
    (sa, sh0), (sb, sh1) = station(cfg["snout"][0]), station(cfg["snout"][1])
    mesh.add_prism(sa, sb, sh0, sh1, SNOUT_FACES, rigid(b["head"]))

    # ── ears ───────────────────────────────────────────────────────────────
    ear = cfg["ear"]
    for sx in (1.0, -1.0):
        base = (sx * ear["base"][0], ear["base"][1], ear["base"][2])
        tip = (sx * ear["tip"][0], ear["tip"][1], ear["tip"][2])
        # up=+X puts the flap's normal on the animal's flank. With the old
        # up=+Z the ears were edge-on from the side and simply vanished.
        mesh.add_plate(base, tip, ear["hw"], "ear", rigid(b["head"]),
                       up=(1, 0, 0))

    # ── legs ───────────────────────────────────────────────────────────────
    for side, sx in (("l", 1.0), ("r", -1.0)):
        for kind, (lx, lz, top_y, knee_y) in (
                ("f", (fx, fz, legs["shoulder_y"], legs["knee_f_y"])),
                ("b", (bx, bz, legs["hip_y"], legs["knee_b_y"]))):
            up_bone = b["leg_%s%s_upper" % (kind, side)]
            lo_bone = b["leg_%s%s_lower" % (kind, side)]
            top = (sx * lx, top_y, lz)
            knee = (sx * lx, knee_y, lz)
            foot = (sx * lx, legs["foot_y"] + legs["hoof"][1] * 2.0, lz)
            uw = legs["upper_hw"]
            lw = legs["lower_hw"]
            hoof_bot = (sx * lx, legs["foot_y"], lz)
            hoof_w = legs["hoof"][0]

            def w_leg(p, _top=top, _knee=knee, _up=up_bone, _lo=lo_bone):
                return blend_along(_top, _knee, [_up, _up, _lo])(p)

            # One tube from shoulder to hoof. As separate prisms the hoof was
            # wider than the ankle above it, leaving an open ring at the joint.
            mesh.add_tube(
                [(top, (uw, uw * 1.15)), (knee, (lw, lw * 1.15)),
                 (foot, (hoof_w * 0.92, hoof_w * 0.92)),
                 (hoof_bot, (hoof_w * 0.9, hoof_w * 1.05))],
                [faces("leg"), LEG_FACES, HOOF_FACES], w_leg,
                cap_a="leg", cap_b="hoof")

    # ── tail ───────────────────────────────────────────────────────────────
    t_a, t_b = cfg["tail"][0], cfg["tail"][1]
    tw = cfg["tail"][2]
    mesh.add_prism(t_a, t_b, (tw, tw), (tw * 0.6, tw * 0.6), faces("tail"),
                   blend_along(t_a, t_b, [b["spine"], b["tail"], b["tail"]]))

    bolt_ons(mesh, rig, cfg, b)
    return mesh, rig


# ─────────────────────────────────────────────────────────────────────────────

#  Animation
#
#  A "poser" maps a time to {bone_name: {"rot": (rx, ry, rz), "pos": (x, y, z)}}.
#  Sampling one at a fixed set of times bakes it into glTF channels.
# ─────────────────────────────────────────────────────────────────────────────


# Trot: diagonal pairs move together.  Reads as purposeful at PS1 framerates.
GAIT = (("f", "l", 0.0), ("b", "r", 0.0), ("f", "r", math.pi), ("b", "l", math.pi))


def leg_pose(kind, side, theta, g):
    """One leg at gait phase `theta`.  Front knees fold back, hind hocks kick
    forward -- the zig-zag that says 'hoofed animal' in silhouette."""
    swing = g["swing_f"] if kind == "f" else g["swing_b"]
    flex = g["flex_f"] if kind == "f" else g["flex_b"]
    sign = -1.0 if kind == "f" else 1.0
    upper = swing * math.sin(theta)
    lower = sign * flex * max(0.0, math.cos(theta))
    return {
        "leg_%s%s_upper" % (kind, side): {"rot": (upper, 0.0, 0.0)},
        "leg_%s%s_lower" % (kind, side): {"rot": (lower, 0.0, 0.0)},
    }


def walk_poser(cfg):
    g = cfg["gait"]
    L = g["walk_len"]

    def poser(t):
        th = 2.0 * math.pi * t / L
        pose = {}
        for kind, side, ph in GAIT:
            pose.update(leg_pose(kind, side, th + ph, g))
        # body rises twice per cycle, as each diagonal pair pushes off
        pose["root"] = {"pos": (0.0, -g["bob"] * math.cos(2.0 * th), 0.0),
                        "rot": (0.0, 0.0, 0.0)}
        pose["spine"] = {"rot": (0.03 * math.sin(2.0 * th),
                                 0.05 * math.sin(th),
                                 g["roll"] * math.sin(th))}
        pose["chest"] = {"rot": (-0.04 * math.sin(2.0 * th), 0.0,
                                 -g["roll"] * 0.7 * math.sin(th))}
        pose["neck"] = {"rot": (g["head_dip"] + 0.05 * math.sin(2.0 * th),
                                0.0, 0.0)}
        pose["head"] = {"rot": (-g["head_dip"] * 0.6 - 0.04 * math.sin(2.0 * th),
                                0.0, 0.0)}
        pose["tail"] = {"rot": (0.0, 0.16 * math.sin(th), 0.0)}
        return pose
    return poser, L


def idle_poser(cfg):
    g = cfg["gait"]
    L = g["idle_len"]

    def poser(t):
        u = t / L
        breath = math.sin(2.0 * math.pi * u)
        # one slow dip to the grass and back per loop
        graze = smoothstep(min(1.0, max(0.0, (u - 0.15) / 0.25))) \
            - smoothstep(min(1.0, max(0.0, (u - 0.62) / 0.23)))
        pose = {}
        for kind, side, _ in GAIT:
            pose.update({
                "leg_%s%s_upper" % (kind, side): {"rot": (0.02 * breath, 0.0, 0.0)},
                "leg_%s%s_lower" % (kind, side): {"rot": (0.0, 0.0, 0.0)},
            })
        pose["root"] = {"pos": (0.0, 0.006 * breath, 0.0), "rot": (0, 0, 0)}
        pose["spine"] = {"rot": (0.012 * breath, 0.0, 0.0)}
        pose["chest"] = {"rot": (0.022 * breath, 0.0, 0.0)}
        pose["neck"] = {"rot": (-g["graze"] * graze + 0.03 * breath, 0.0, 0.0)}
        pose["head"] = {"rot": (-g["graze"] * 0.45 * graze, 0.0,
                                0.05 * math.sin(6.0 * math.pi * u))}
        pose["tail"] = {"rot": (0.0, 0.22 * math.sin(4.0 * math.pi * u), 0.0)}
        return pose
    return poser, L


def death_poser(cfg, ground=0.0):
    """Legs buckle, the body pitches, then rolls onto its side and settles.

    `ground` is the correction make_animations measures and feeds back, so the
    carcass ends up resting on the floor instead of hovering or sinking."""
    g = cfg["gait"]
    L = g["death_len"]
    mid = cfg["torso"][len(cfg["torso"]) // 2]
    body_y, body_hw = mid[1], mid[2]
    roll = g["death_roll"]
    # Where the root has to go so the rolled-over body rests on the ground.
    # Rolling by phi about the root sends the torso centre from (0, body_y) to
    # (-body_y sin phi, body_y cos phi); it wants to end up half a body-width
    # up and roughly back over where the animal was standing.
    drop_x = body_y * math.sin(roll) * 0.92
    drop_y = body_hw - body_y * math.cos(roll) + ground

    def ramp(t, a, b):
        return smoothstep((t - a) / (b - a)) if b > a else 0.0

    def poser(t):
        u = t / L
        buckle = ramp(u, 0.04, 0.34)
        fall = ramp(u, 0.22, 0.72)
        settle = ramp(u, 0.68, 1.0)
        # a last startled kick before the legs give out
        kick = math.sin(math.pi * min(1.0, u / 0.22)) * (1.0 - fall)

        pose = {}
        for kind, side, ph in GAIT:
            s = 1.0 if side == "l" else -1.0
            if kind == "f":
                up = -1.05 * buckle + 0.25 * kick * s
                lo = -1.5 * buckle - 0.25 * settle
            else:
                up = 0.85 * buckle - 0.3 * kick * s
                lo = 1.35 * buckle + 0.2 * settle
            pose["leg_%s%s_upper" % (kind, side)] = {"rot": (up, 0.12 * kick * s, 0.0)}
            pose["leg_%s%s_lower" % (kind, side)] = {"rot": (lo, 0.0, 0.0)}

        pose["root"] = {
            "pos": (drop_x * fall, drop_y * fall, 0.0),
            "rot": (0.12 * fall, 0.0, roll * fall),
        }
        pose["spine"] = {"rot": (-0.15 * buckle, 0.1 * fall, 0.0)}
        pose["chest"] = {"rot": (-0.28 * buckle + 0.1 * settle, 0.0, 0.0)}
        pose["neck"] = {"rot": (0.45 * kick - 0.55 * fall, 0.18 * fall, 0.0)}
        pose["head"] = {"rot": (0.2 * kick - 0.35 * settle, 0.3 * fall, 0.0)}
        pose["tail"] = {"rot": (-0.3 * fall, 0.25 * kick, 0.0)}
        return pose
    return poser, L


def make_animations(rig, cfg, mesh):
    anims = {}
    for name, factory, keys in (("idle", idle_poser, 17),
                                ("walk", walk_poser, 17),
                                ("death", death_poser, 21)):
        poser, L = factory(cfg)
        if name == "death":
            # Antlers, tusks and folded legs all move the lowest point around,
            # so where the collapsed body actually lands is measured rather
            # than derived, and the whole clip is re-baked with the offset.
            lo, _ = posed_bounds(mesh, rig, poser(L))
            poser, L = death_poser(cfg, ground=-lo[1])
        times = [round(L * i / (keys - 1), 5) for i in range(keys)]
        anims[name] = {"length": L, "channels": bake(rig, times, poser)}
    return anims


# ─────────────────────────────────────────────────────────────────────────────
#  Bolt-on detail: horns, tusks, antlers, crests, fleece
# ─────────────────────────────────────────────────────────────────────────────

def bolt_ons(mesh, rig, cfg, b):
    """Data-driven extras.  A "stick" is a polyline with a radius per point --
    a boar's tusk, a stag's antler and a ram's horn are all the same code."""
    for spec in cfg.get("horns", []):
        bone = rigid(b[spec.get("bone", "head")])
        region = spec.get("region", "horn")
        for mirror in ((1.0, -1.0) if spec.get("mirror", True) else (1.0,)):
            pts = [(mirror * x, y, z) for (x, y, z) in spec["pts"]]
            rad = spec["r"]
            for i in range(len(pts) - 1):
                mesh.add_prism(pts[i], pts[i + 1],
                               (rad[i], rad[i]), (rad[i + 1], rad[i + 1]),
                               faces(region), bone)

    for spec in cfg.get("crest", []):
        # bristly ridge along the spine -- flat plates, cheap and very PS1
        bone = rigid(b[spec.get("bone", "chest")])
        n = spec["count"]
        for i in range(n):
            t = i / max(1, n - 1)
            z = spec["z0"] + (spec["z1"] - spec["z0"]) * t
            y = spec["y0"] + (spec["y1"] - spec["y0"]) * t
            h = spec["h"] * (0.55 + 0.45 * math.sin(math.pi * t))
            mesh.add_plate((0.0, y, z), (0.0, y + h, z - h * 0.35),
                           spec["hw"], spec.get("region", "back"), bone,
                           up=(1, 0, 0))

    for spec in cfg.get("fleece", []):
        bone = rigid(b[spec.get("bone", "spine")])
        for mirror in ((1.0, -1.0) if spec.get("mirror", False) else (1.0,)):
            a = (mirror * spec["a"][0], spec["a"][1], spec["a"][2])
            c = (mirror * spec["b"][0], spec["b"][1], spec["b"][2])
            mesh.add_prism(a, c, spec["ha"], spec["hb"],
                           faces(spec.get("region", "body")), bone)


# ─────────────────────────────────────────────────────────────────────────────
#  Juvenile proportions
# ─────────────────────────────────────────────────────────────────────────────

def _sc_station(t, s):
    return (t[0] * s, t[1] * s, t[2] * s, t[3] * s)


def juvenile(cfg, s, head=1.30, snout=0.72, neck=0.72, leg=0.88):
    """Scale down, then re-proportion: young animals are all head and no leg."""
    c = {k: cfg[k] for k in cfg}
    c["torso"] = [_sc_station(t, s) for t in cfg["torso"]]
    for key in ("neck", "head", "snout"):
        c[key] = [_sc_station(t, s) for t in cfg[key]]
    c["ear"] = {"base": tuple(v * s for v in cfg["ear"]["base"]),
                "tip": tuple(v * s for v in cfg["ear"]["tip"]),
                "hw": cfg["ear"]["hw"] * s}
    c["legs"] = {k: (tuple(v * s for v in val) if isinstance(val, tuple)
                     else val * s) for k, val in cfg["legs"].items()}
    c["tail"] = [tuple(v * s for v in cfg["tail"][0]),
                 tuple(v * s for v in cfg["tail"][1]), cfg["tail"][2] * s]
    c["gait"] = dict(cfg["gait"])
    c["gait"]["bob"] = cfg["gait"]["bob"] * s
    c["gait"]["walk_len"] = cfg["gait"]["walk_len"] * 0.78   # shorter legs, faster steps
    c["horns"] = []                                          # no tusks, no antlers yet
    c["crest"] = []                                          # no mane yet either
    c["fleece"] = []
    for x in cfg.get("fleece", []):
        y = dict(x)
        for k in ("a", "b", "ha", "hb"):
            y[k] = tuple(v * s for v in x[k])
        c["fleece"].append(y)

    # ── shorter legs: drop the whole body, keep the joints proportional ─────
    d = c["legs"]["shoulder_y"] * (1.0 - leg)
    for key in ("torso", "neck", "head", "snout"):
        c[key] = [(t[0], t[1] - d, t[2], t[3]) for t in c[key]]
    for k in ("base", "tip"):
        c["ear"][k] = (c["ear"][k][0], c["ear"][k][1] - d, c["ear"][k][2])
    c["tail"] = [(p[0], p[1] - d, p[2]) for p in c["tail"][:2]] + [c["tail"][2]]
    for k in ("shoulder_y", "hip_y", "knee_f_y", "knee_b_y"):
        c["legs"][k] *= leg
    for spec in c["crest"]:
        spec["y0"] -= d
        spec["y1"] -= d
    for spec in c["fleece"]:
        spec["a"] = (spec["a"][0], spec["a"][1] - d, spec["a"][2])
        spec["b"] = (spec["b"][0], spec["b"][1] - d, spec["b"][2])

    # ── stubby neck: pull the whole head group back toward the shoulders ────
    na, nb = c["neck"][0], c["neck"][1]
    dz = (nb[0] - na[0]) * (1.0 - neck)
    dy = (nb[1] - na[1]) * (1.0 - neck)
    c["neck"][1] = (nb[0] - dz, nb[1] - dy, nb[2], nb[3])
    for key in ("head", "snout"):
        c[key] = [(t[0] - dz, t[1] - dy, t[2], t[3]) for t in c[key]]
    for k in ("base", "tip"):
        c["ear"][k] = (c["ear"][k][0], c["ear"][k][1] - dy, c["ear"][k][2] - dz)

    # ── blunt muzzle, oversized skull ──────────────────────────────────────
    sa, sb = c["snout"][0], c["snout"][1]
    c["snout"] = [sa, (sa[0] + (sb[0] - sa[0]) * snout,
                       sa[1] + (sb[1] - sa[1]) * snout,
                       sb[2] * head, sb[3] * head)]
    c["snout"][0] = (sa[0], sa[1], sa[2] * head, sa[3] * head)
    c["head"] = [(t[0], t[1], t[2] * head, t[3] * head) for t in c["head"]]
    c["neck"][1] = (c["neck"][1][0], c["neck"][1][1],
                    c["neck"][1][2] * head * 0.9, c["neck"][1][3] * head * 0.9)
    c["ear"]["hw"] *= head
    return c


# ─────────────────────────────────────────────────────────────────────────────
#  Species
#
#  Stations run rear -> front as (z, y, half_width, half_height); the animal
#  faces -Z.  Dimensions are metres and follow the real animals of Parnitha.
# ─────────────────────────────────────────────────────────────────────────────

def gait(**over):
    g = {"swing_f": 0.42, "swing_b": 0.38, "flex_f": 0.52, "flex_b": 0.46,
         "bob": 0.020, "roll": 0.035, "head_dip": 0.05, "graze": 0.55,
         "walk_len": 0.72, "idle_len": 3.6, "death_len": 1.7, "death_roll": 1.45}
    g.update(over)
    return g


# ── Wild boar: bulky, low to the ground, front-heavy, all shoulder ──────────
BOAR = {
    "torso": [(0.60, 0.50, 0.16, 0.16),
              (0.20, 0.54, 0.24, 0.22),
              (-0.20, 0.58, 0.26, 0.27),      # withers hump
              (-0.50, 0.55, 0.20, 0.23)],
    "neck":  [(-0.50, 0.58, 0.19, 0.21), (-0.66, 0.58, 0.15, 0.17)],
    "head":  [(-0.64, 0.58, 0.15, 0.17), (-0.86, 0.53, 0.11, 0.12)],
    "snout": [(-0.84, 0.54, 0.09, 0.09), (-1.04, 0.45, 0.055, 0.05)],
    "ear":   {"base": (0.098, 0.675, -0.60), "tip": (0.175, 0.805, -0.555),
              "hw": 0.060},
    "legs":  {"front": (0.155, -0.30), "back": (0.165, 0.40),
              "shoulder_y": 0.44, "hip_y": 0.43, "knee_f_y": 0.23,
              "knee_b_y": 0.22, "foot_y": 0.0, "upper_hw": 0.062,
              "lower_hw": 0.046, "hoof": (0.052, 0.034)},
    "tail":  [(0.0, 0.50, 0.60), (0.0, 0.26, 0.66), 0.026],
    "horns": [  # tusks: short, up-curving, either side of the muzzle
        {"pts": [(0.072, 0.48, -0.90), (0.086, 0.53, -0.99), (0.090, 0.60, -1.01)],
         "r": [0.020, 0.014, 0.006]},
    ],
    "crest": [{"z0": -0.52, "z1": 0.10, "y0": 0.85, "y1": 0.76,
               "h": 0.13, "hw": 0.012, "count": 5, "bone": "chest"}],
    "gait": gait(swing_f=0.36, swing_b=0.34, bob=0.016, walk_len=0.62,
                 graze=0.40, idle_len=3.2, death_len=1.5),
}

# ── Red deer: tall, long-legged, long-necked, antlered ──────────────────────
DEER = {
    "torso": [(0.70, 0.84, 0.18, 0.20),
              (0.28, 0.89, 0.23, 0.25),
              (-0.20, 0.91, 0.23, 0.26),
              (-0.56, 0.89, 0.19, 0.23)],
    "neck":  [(-0.56, 0.96, 0.15, 0.17), (-0.80, 1.20, 0.105, 0.115)],
    "head":  [(-0.80, 1.22, 0.105, 0.125), (-0.95, 1.13, 0.078, 0.090)],
    "snout": [(-0.92, 1.15, 0.068, 0.075), (-1.08, 1.08, 0.048, 0.048)],
    "ear":   {"base": (0.095, 1.265, -0.745), "tip": (0.275, 1.335, -0.695),
              "hw": 0.072},
    "legs":  {"front": (0.165, -0.36), "back": (0.185, 0.48),
              "shoulder_y": 0.78, "hip_y": 0.78, "knee_f_y": 0.43,
              "knee_b_y": 0.41, "foot_y": 0.0, "upper_hw": 0.055,
              "lower_hw": 0.036, "hoof": (0.044, 0.030)},
    "tail":  [(0.0, 0.86, 0.69), (0.0, 0.70, 0.735), 0.026],
    "horns": [  # antler: main beam sweeping up and back
        {"pts": [(0.07, 1.31, -0.80), (0.14, 1.49, -0.75),
                 (0.19, 1.65, -0.65), (0.17, 1.79, -0.52)],
         "r": [0.034, 0.026, 0.019, 0.011]},
        {"pts": [(0.120, 1.45, -0.77), (0.20, 1.55, -0.90)],      # brow tine
         "r": [0.019, 0.008]},
        {"pts": [(0.175, 1.59, -0.69), (0.28, 1.70, -0.80)],      # trez tine
         "r": [0.017, 0.008]},
        {"pts": [(0.185, 1.67, -0.61), (0.25, 1.87, -0.60)],      # crown tine
         "r": [0.016, 0.007]},
    ],
    "gait": gait(swing_f=0.46, swing_b=0.42, bob=0.026, walk_len=0.78,
                 graze=0.72, idle_len=4.0, death_len=1.8),
}

# ── Sheep: short, round, fleeced. The barrel is the fleece, not the ribcage,
#    so the wool sits wider than the torso and the body tapers away at both
#    ends -- otherwise a pale quadruped reads as a crate on sticks.
SHEEP = {
    # the barrel IS the fleece: one tapered form, widest just ahead of centre
    "torso": [(0.40, 0.52, 0.160, 0.170),
              (0.16, 0.55, 0.235, 0.225),
              (-0.14, 0.56, 0.245, 0.235),
              (-0.40, 0.53, 0.175, 0.190)],
    "neck":  [(-0.40, 0.57, 0.125, 0.135), (-0.55, 0.65, 0.098, 0.105)],
    "head":  [(-0.55, 0.65, 0.093, 0.103), (-0.69, 0.615, 0.070, 0.080)],
    "snout": [(-0.67, 0.625, 0.060, 0.066), (-0.79, 0.565, 0.041, 0.041)],
    "ear":   {"base": (0.086, 0.665, -0.555), "tip": (0.193, 0.645, -0.515),
              "hw": 0.050},
    "legs":  {"front": (0.122, -0.25), "back": (0.132, 0.27),
              "shoulder_y": 0.44, "hip_y": 0.44, "knee_f_y": 0.235,
              "knee_b_y": 0.225, "foot_y": 0.0, "upper_hw": 0.042,
              "lower_hw": 0.030, "hoof": (0.036, 0.025)},
    "tail":  [(0.0, 0.52, 0.40), (0.0, 0.35, 0.44), 0.030],
    "horns": [  # ewe's horn: short, curling back around the ear
        {"pts": [(0.060, 0.705, -0.59), (0.103, 0.735, -0.55),
                 (0.123, 0.705, -0.50)],
         "r": [0.019, 0.014, 0.008]},
    ],
    "fleece": [  # woolly ruff where the neck leaves the shoulders
        {"a": (0.0, 0.555, -0.36), "b": (0.0, 0.590, -0.52),
         "ha": (0.195, 0.185), "hb": (0.150, 0.145), "bone": "chest"},
    ],
    "gait": gait(swing_f=0.34, swing_b=0.32, bob=0.014, walk_len=0.66,
                 graze=0.60, idle_len=3.4, death_len=1.5),
}


# ─────────────────────────────────────────────────────────────────────────────
#  Atlas painting per species
# ─────────────────────────────────────────────────────────────────────────────

def paint_boar(a, baby):
    if baby:
        a.fill("body", (132, 100, 64), "fur", accent=(158, 124, 84))
        a.stripes("body", (78, 54, 34), period=8, width=3)
        a.fill("back", (112, 84, 54), "fur")
        a.stripes("back", (68, 46, 30), period=7, width=3)
        a.fill("belly", (150, 122, 90), "hide")
        a.fill("head", (124, 94, 62), "fur")
        a.fill("face", (116, 88, 58), "fur")
        a.fill("snout", (138, 106, 96), "hide")
        a.fill("leg", (96, 70, 46), "fur")
        a.fill("tail", (104, 78, 50), "fur")
        a.fill("ear", (110, 82, 54), "fur")
    else:
        a.fill("body", (62, 52, 44), "fur", accent=(84, 72, 60))
        a.fill("back", (44, 38, 34), "fur", accent=(70, 62, 54))
        a.fill("belly", (78, 66, 54), "hide")
        a.fill("head", (54, 46, 40), "fur")
        a.fill("face", (48, 41, 36), "fur")
        a.fill("snout", (92, 74, 68), "hide")
        a.fill("leg", (40, 34, 30), "fur")
        a.fill("tail", (46, 39, 34), "fur")
        a.fill("ear", (48, 40, 35), "fur")
    # A young animal's eye is bigger in a smaller face; that ratio does
    # most of the work of reading as a juvenile.
    a.paint_eye("face", (58, 48, 38), (10, 9, 9),
                rx=0.17 if baby else 0.13, ry=0.135 if baby else 0.105)
    a.fill("hoof", (26, 23, 22), "flat", amount=6)
    a.fill("horn", (214, 206, 180), "gloss", amount=8)   # tusk ivory


def paint_deer(a, baby):
    if baby:
        a.fill("body", (158, 114, 70), "fur", accent=(182, 140, 96))
        a.speckle("body", (226, 214, 190), count=26, size=2)
        a.fill("back", (138, 98, 60), "fur")
        a.speckle("back", (222, 210, 186), count=14, size=2)
        a.fill("belly", (196, 174, 146), "hide")
        a.fill("head", (156, 114, 72), "fur")
        a.fill("face", (148, 108, 68), "fur")
        a.fill("snout", (66, 54, 48), "hide")
        a.fill("leg", (144, 104, 64), "fur")
        a.fill("tail", (176, 154, 124), "fur")
        a.fill("ear", (150, 110, 70), "fur")
    else:
        a.fill("body", (124, 84, 50), "fur", accent=(146, 104, 64))
        a.fill("back", (102, 68, 40), "fur", accent=(126, 88, 54))
        a.fill("belly", (172, 148, 118), "hide")
        a.fill("head", (128, 90, 56), "fur")
        a.fill("face", (120, 84, 52), "fur")
        a.fill("snout", (54, 45, 40), "hide")
        a.fill("leg", (112, 78, 46), "fur")
        a.fill("tail", (152, 126, 96), "fur")
        a.fill("ear", (118, 82, 52), "fur")
    # A young animal's eye is bigger in a smaller face; that ratio does
    # most of the work of reading as a juvenile.
    a.paint_eye("face", (46, 33, 22), (10, 8, 8),
                rx=0.17 if baby else 0.13, ry=0.135 if baby else 0.105)
    a.fill("hoof", (28, 25, 24), "flat", amount=6)
    a.fill("horn", (146, 122, 88), "gloss", amount=10)   # antler bone


def paint_sheep(a, baby):
    if baby:
        a.fill("body", (226, 222, 214), "wool", amount=10)
        a.fill("back", (216, 212, 204), "wool", amount=10)
        a.fill("belly", (222, 218, 210), "wool", amount=8)
        a.fill("head", (198, 182, 156), "fur")
        a.fill("face", (188, 172, 148), "fur")
        a.fill("snout", (96, 88, 82), "hide")
        a.fill("leg", (170, 158, 138), "fur")
        a.fill("tail", (222, 218, 210), "wool")
        a.fill("ear", (208, 200, 186), "fur")
    else:
        a.fill("body", (204, 198, 186), "wool", amount=12)
        a.fill("back", (192, 186, 174), "wool", amount=12)
        a.fill("belly", (184, 178, 166), "wool", amount=10)
        a.fill("head", (168, 148, 118), "fur")
        a.fill("face", (156, 138, 110), "fur")
        a.fill("snout", (74, 68, 62), "hide")
        a.fill("leg", (138, 126, 106), "fur")
        a.fill("tail", (200, 194, 182), "wool")
        a.fill("ear", (188, 176, 156), "fur")
    # A young animal's eye is bigger in a smaller face; that ratio does
    # most of the work of reading as a juvenile.
    a.paint_eye("face", (74, 63, 50), (14, 12, 10),
                rx=0.17 if baby else 0.13, ry=0.135 if baby else 0.105)
    a.fill("hoof", (30, 27, 26), "flat", amount=6)
    a.fill("horn", (194, 178, 144), "gloss", amount=10)


# ─────────────────────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────────────────────

FAMILY = [
    # name,             cfg,                        painter,     seed,     score
    ("boar_new",        BOAR,                       paint_boar,  20250819,  6000),
    ("baby_boar_new",   juvenile(BOAR, 0.44, head=1.34, snout=0.66),
                                                    paint_boar,  20250820, 12000),
    ("deer_new",        DEER,                       paint_deer,  20250821,  5000),
    ("baby_deer_new",   juvenile(DEER, 0.50, head=1.28, snout=0.70, neck=0.78),
                                                    paint_deer,  20250822, 10000),
    ("sheep_new",       SHEEP,                      paint_sheep, 20250823,  5000),
    ("baby_sheep_new",  juvenile(SHEEP, 0.52, head=1.26, snout=0.74),
                                                    paint_sheep, 20250824, 10000),
]


def body_metrics(cfg):
    """Collision proxy and stride, measured off the body plan rather than the
    mesh bounds -- antlers and tusks must not inflate either."""
    torso = cfg["torso"]
    legs = cfg["legs"]
    top = max(t[1] + t[3] for t in torso)
    width = 2.0 * max(t[2] for t in torso)
    front = cfg["snout"][1][0]
    back = max(cfg["tail"][0][2], cfg["tail"][1][2], torso[0][0])
    # A trot advances the body by one stance sweep per diagonal pair, twice a
    # cycle; the sweep is the arc the leg swings through about the shoulder.
    stride = 4.0 * legs["shoulder_y"] * math.sin(cfg["gait"]["swing_f"])
    return {
        "collider_size": [round(width, 4), round(top, 4), round(back - front, 4)],
        "collider_y": round(top * 0.5, 4),
        "collider_z": round((back + front) * 0.5, 4),
        "walk_cycle_distance": round(stride, 4),
        "shoulder_height": round(legs["shoulder_y"], 4),
    }


def main():
    os.makedirs(MODEL_DIR, exist_ok=True)
    os.makedirs(TEX_DIR, exist_ok=True)

    manifest = []
    for name, cfg, painter, seed, score in FAMILY:
        baby = name.startswith("baby")

        atlas = Atlas(seed)
        painter(atlas, baby)
        png_name = name.replace("_new", "_atlas_new") + ".png"
        png_path = os.path.join(TEX_DIR, png_name)
        atlas.save(png_path)
        write_import(png_path)

        mesh, rig = build_animal(cfg)
        anims = make_animations(rig, cfg, mesh)
        export_gltf(os.path.join(MODEL_DIR, name + ".gltf"), name, mesh, rig,
                    anims, "../../textures/animals/" + png_name)

        entry = {
            "name": name,
            "gltf": "res://models/animals/%s.gltf" % name,
            "atlas": "res://textures/animals/%s" % png_name,
            "scene": "res://scenes/animals/%s.tscn" % name,
            "score_value": score,
            "tris": mesh.tris,
            "bones": len(rig.names),
            "animations": {k: round(v["length"], 4) for k, v in anims.items()},
        }
        entry.update(body_metrics(cfg))

        ys = [p[1] for p in mesh.pos]
        zs = [p[2] for p in mesh.pos]
        # full bounds, antlers and tusks included -- what a skinned AABB in the
        # bind pose must come out as if the model survived the round trip
        entry["mesh_height"] = round(max(ys) - min(ys), 4)
        entry["mesh_length"] = round(max(zs) - min(zs), 4)
        entry["mesh_floor"] = round(min(ys), 4)
        manifest.append(entry)
        print("%-16s %4d tris  %3d verts  %2d bones  h=%.2fm l=%.2fm  %s"
              % (name, mesh.tris, len(mesh.pos), len(rig.names),
                 max(ys) - min(ys), max(zs) - min(zs), png_name))

    with open(os.path.join(MODEL_DIR, "animals_new.json"), "w",
              encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1)
    print("wrote models/animals/animals_new.json")


if __name__ == "__main__":
    main()
