"""Shared PS1-era modelling core.

The geometry, rigging, skinning and glTF machinery behind every generated model
in this project. tools/gen_animals_new.py builds the bestiary on top of it and
tools/gen_player_shadow_new.py builds the player's shadow body; neither knows
anything the other does.

Conventions throughout: +Y is up, -Z is forward, metres, and every surface is
flat-shaded and unwelded -- 24 vertices to a box -- which is what gives the
hard-facetted PlayStation read.
"""

import base64
import json
import math
import os
import struct
import zlib

TEX = 128  # atlas edge, in pixels

#  PNG output  (stdlib only -- no Pillow in this toolchain)
# ─────────────────────────────────────────────────────────────────────────────

def write_png(path, w, h, rgb):
    """rgb is a flat bytearray of w*h*3 samples, row-major from the top."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)                       # filter type 0 (None)
        raw += rgb[y * w * 3:(y + 1) * w * 3]

    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


# Godot import preset, copied from the existing textures/ps1 set: lossless,
# mipmapped, and detect_3d disabled so first use in a 3D scene cannot quietly
# re-import the sheet as VRAM-compressed and smear the pixels.
IMPORT_PRESET = """[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(png_path):
    """Only written when absent -- Godot owns the [remap]/[deps] sections it
    adds on first import, and clobbering those forces a needless re-import."""
    path = png_path + ".import"
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(IMPORT_PRESET)


# ─────────────────────────────────────────────────────────────────────────────
#  Small vector helpers
# ─────────────────────────────────────────────────────────────────────────────

def v_add(a, b):  return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def v_sub(a, b):  return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def v_mul(a, s):  return (a[0] * s, a[1] * s, a[2] * s)


def v_cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def v_norm(a):
    m = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    return (0.0, 0.0, 0.0) if m < 1e-9 else (a[0] / m, a[1] / m, a[2] / m)



def v_rotate(v, axis, ang):
    """Rodrigues rotation of `v` about a unit `axis`."""
    c, si = math.cos(ang), math.sin(ang)
    return v_add(v_add(v_mul(v, c), v_mul(v_cross(axis, v), si)),
                 v_mul(axis, v_dot(axis, v) * (1.0 - c)))


def clamp01(t):
    return 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)


def smoothstep(t):
    t = clamp01(t)
    return t * t * (3.0 - 2.0 * t)


def quat_axis(axis, ang):
    """Quaternion (x, y, z, w) -- glTF's component order."""
    s = math.sin(ang * 0.5)
    a = v_norm(axis)
    return (a[0] * s, a[1] * s, a[2] * s, math.cos(ang * 0.5))


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def quat_euler(rx, ry, rz):
    """X, then Y, then Z -- applied in that order."""
    return quat_mul(quat_axis((0, 0, 1), rz),
                    quat_mul(quat_axis((0, 1, 0), ry), quat_axis((1, 0, 0), rx)))


# ─────────────────────────────────────────────────────────────────────────────
#  Armature
# ─────────────────────────────────────────────────────────────────────────────

class Rig:
    """Bind pose is rotation-free: a bone is just a named point plus a parent."""

    def __init__(self):
        self.names, self.parents, self.pos = [], [], []

    def add(self, name, parent, pos):
        self.names.append(name)
        self.parents.append(-1 if parent is None else self.idx(parent))
        self.pos.append(pos)
        return len(self.names) - 1

    def idx(self, name):
        return self.names.index(name)

    def local(self, i):
        p = self.parents[i]
        return self.pos[i] if p < 0 else v_sub(self.pos[i], self.pos[p])

    def inverse_bind(self, i):
        """Column-major 4x4: bind pose is a pure translation, so the inverse is
        just the negated position."""
        x, y, z = self.pos[i]
        return [1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  -x, -y, -z, 1]


# ─────────────────────────────────────────────────────────────────────────────
#  Mesh
# ─────────────────────────────────────────────────────────────────────────────

class Mesh:
    """Flat-shaded, hard-edged, unwelded -- exactly what a PlayStation would eat."""

    def __init__(self, uv_lookup):
        """`uv_lookup(region_name)` returns (u0, v0, u1, v1) on the atlas. A
        model with no texture can pass a lambda returning the whole sheet."""
        self._uv = uv_lookup
        self.pos, self.nrm, self.uv = [], [], []
        self.joints, self.weights = [], []
        self.idx = []

    def add_quad(self, p0, p1, p2, p3, region, weight_fn, rot=0):
        """p0..p3 wound counter-clockwise seen from outside the surface.

        Flat quads become one facet with one normal. Where a tube bends, its
        side quads come out warped -- the two rings sit in different planes --
        and a single normal then contradicts one of the two triangles. Those
        are split into a facet each instead.
        """
        u0, v0, u1, v1 = self._uv(region)
        corners = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
        corners = corners[rot:] + corners[:rot]

        n1 = v_norm(v_cross(v_sub(p1, p0), v_sub(p2, p0)))
        n2 = v_norm(v_cross(v_sub(p2, p0), v_sub(p3, p0)))
        if v_dot(n1, n2) > 0.999:
            base = self._emit((p0, p1, p2, p3), corners, n1, weight_fn)
            self.idx += [base, base + 1, base + 2, base, base + 2, base + 3]
            return
        a = self._emit((p0, p1, p2), (corners[0], corners[1], corners[2]),
                       n1, weight_fn)
        self.idx += [a, a + 1, a + 2]
        b = self._emit((p0, p2, p3), (corners[0], corners[2], corners[3]),
                       n2, weight_fn)
        self.idx += [b, b + 1, b + 2]

    def _emit(self, points, uvs, n, weight_fn):
        base = len(self.pos)
        for p, uv in zip(points, uvs):
            self.pos.append(p)
            self.nrm.append(n)
            self.uv.append(uv)
            js, ws = normalise_weights(weight_fn(p))
            self.joints.append(js)
            self.weights.append(ws)
        return base

    def add_prism(self, a, b, a_half, b_half, regions, weight_fn):
        """A box swept from cap `a` to cap `b`.  `*_half` is (half-width,
        half-height) in the segment's own frame, so a limb can taper.

        `regions` maps face key -> atlas region:
            cap_a  cap_b  side_p  side_n  side_u  side_d
        """
        f = v_norm(v_sub(b, a))
        ref = (0, 1, 0) if abs(f[1]) < 0.9 else (0, 0, 1)
        r = v_norm(v_cross(ref, f))
        u = v_cross(f, r)

        def corner(c, half, sr, su):
            return v_add(c, v_add(v_mul(r, sr * half[0]), v_mul(u, su * half[1])))

        # a-cap corners, then b-cap corners: (-r,-u) (+r,-u) (+r,+u) (-r,+u)
        a0 = corner(a, a_half, -1, -1); a1 = corner(a, a_half, 1, -1)
        a2 = corner(a, a_half, 1, 1);   a3 = corner(a, a_half, -1, 1)
        b0 = corner(b, b_half, -1, -1); b1 = corner(b, b_half, 1, -1)
        b2 = corner(b, b_half, 1, 1);   b3 = corner(b, b_half, -1, 1)

        g = regions
        self.add_quad(a1, a0, a3, a2, g["cap_a"], weight_fn)     # facing -f
        self.add_quad(b0, b1, b2, b3, g["cap_b"], weight_fn)     # facing +f
        self.add_quad(a1, b1, b2, a2, g["side_p"], weight_fn)    # facing +r
        self.add_quad(b0, a0, a3, b3, g["side_n"], weight_fn)    # facing -r
        self.add_quad(a3, b3, b2, a2, g["side_u"], weight_fn)    # facing +u
        self.add_quad(b0, a0, a1, b1, g["side_d"], weight_fn)    # facing -u


    def add_tube(self, rings, segments, weight_fn, cap_a=None, cap_b=None):
        """A body lofted through a chain of cross-sections.

        `add_prism` derives its frame from its own two endpoints, so where a
        chain bends, one segment's end ring and the next one's start ring tilt
        differently and stand apart -- a 2cm slit down the flank that reads as
        a hole straight through the animal. A tube computes one ring per
        station and hands the same four corners to both neighbouring segments,
        so the surface closes no matter how the chain turns.

        rings:    [(centre, (half_width, half_height)), ...]
        segments: one face-region dict per gap between rings, using the
                  side_p / side_n / side_u / side_d keys
        cap_a / cap_b: region for the end caps, or None to leave an end open
        """
        assert len(segments) == len(rings) - 1, "one segment per gap"
        centres = [c for c, _ in rings]

        # Frame is carried along the chain by the smallest rotation from one
        # tangent to the next, rather than rebuilt per segment: rebuilding lets
        # the reference-axis choice flip mid-chain and twists the tube.
        tangents = []
        for i in range(len(centres)):
            if i == 0:
                t = v_sub(centres[1], centres[0])
            elif i == len(centres) - 1:
                t = v_sub(centres[-1], centres[-2])
            else:
                t = v_add(v_norm(v_sub(centres[i], centres[i - 1])),
                          v_norm(v_sub(centres[i + 1], centres[i])))
            tangents.append(v_norm(t))

        f0 = tangents[0]
        ref = (0, 1, 0) if abs(f0[1]) < 0.9 else (0, 0, 1)
        r = v_norm(v_cross(ref, f0))
        u = v_cross(f0, r)

        corners = []
        for i, (centre, half) in enumerate(rings):
            if i > 0:
                axis = v_cross(tangents[i - 1], tangents[i])
                m = math.sqrt(v_dot(axis, axis))
                if m > 1e-9:
                    ang = math.asin(max(-1.0, min(1.0, m)))
                    axis = v_mul(axis, 1.0 / m)
                    r = v_norm(v_rotate(r, axis, ang))
                    u = v_norm(v_rotate(u, axis, ang))
            corners.append([
                v_add(centre, v_add(v_mul(r, -half[0]), v_mul(u, -half[1]))),
                v_add(centre, v_add(v_mul(r, half[0]), v_mul(u, -half[1]))),
                v_add(centre, v_add(v_mul(r, half[0]), v_mul(u, half[1]))),
                v_add(centre, v_add(v_mul(r, -half[0]), v_mul(u, half[1]))),
            ])

        for i, g in enumerate(segments):
            a0, a1, a2, a3 = corners[i]
            b0, b1, b2, b3 = corners[i + 1]
            self.add_quad(a1, b1, b2, a2, g["side_p"], weight_fn)
            self.add_quad(b0, a0, a3, b3, g["side_n"], weight_fn)
            self.add_quad(a3, b3, b2, a2, g["side_u"], weight_fn)
            self.add_quad(b0, a0, a1, b1, g["side_d"], weight_fn)

        if cap_a:
            a0, a1, a2, a3 = corners[0]
            self.add_quad(a1, a0, a3, a2, cap_a, weight_fn)
        if cap_b:
            b0, b1, b2, b3 = corners[-1]
            self.add_quad(b0, b1, b2, b3, cap_b, weight_fn)

    def add_plate(self, a, b, half_w, region, weight_fn, up=(0, 1, 0)):
        """A two-sided flat quad -- crests, ear flaps, tail tufts."""
        f = v_norm(v_sub(b, a))
        r = v_norm(v_cross(up, f))
        if r == (0.0, 0.0, 0.0):
            r = (1.0, 0.0, 0.0)
        p0 = v_add(a, v_mul(r, -half_w)); p1 = v_add(a, v_mul(r, half_w))
        p2 = v_add(b, v_mul(r, half_w));  p3 = v_add(b, v_mul(r, -half_w))
        self.add_quad(p0, p1, p2, p3, region, weight_fn)
        self.add_quad(p3, p2, p1, p0, region, weight_fn)

    @property
    def tris(self):
        return len(self.idx) // 3


def normalise_weights(pairs):
    """glTF wants exactly four influences per vertex, summing to 1."""
    pairs = sorted((p for p in pairs if p[1] > 0.0), key=lambda p: -p[1])[:4]
    total = sum(w for _, w in pairs) or 1.0
    js = [0, 0, 0, 0]
    ws = [0.0, 0.0, 0.0, 0.0]
    for i, (j, w) in enumerate(pairs):
        js[i] = j
        ws[i] = w / total
    return js, ws


def rigid(bone):
    return lambda p: [(bone, 1.0)]


def blend_axis(axis, lo, hi, bone_lo, bone_hi):
    """Weight ramp across a joint, so the skin creases instead of shearing."""
    def fn(p):
        t = smoothstep((p[axis] - lo) / (hi - lo)) if hi != lo else 0.0
        return [(bone_lo, 1.0 - t), (bone_hi, t)]
    return fn


ALL_FACES = ("cap_a", "cap_b", "side_p", "side_n", "side_u", "side_d")


def faces(default, **overrides):
    g = {k: default for k in ALL_FACES}
    g.update(overrides)
    return g


# ─────────────────────────────────────────────────────────────────────────────
#  glTF 2.0 export
# ─────────────────────────────────────────────────────────────────────────────

class GltfBuilder:
    def __init__(self):
        self.blob = bytearray()
        self.views = []
        self.accessors = []

    def _view(self, data, target=None):
        while len(self.blob) % 4:            # accessors must stay 4-aligned
            self.blob.append(0)
        offset = len(self.blob)
        self.blob += data
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        self.views.append(view)
        return len(self.views) - 1

    def accessor(self, values, kind, comp_type, target=None, minmax=False):
        """`values` is a list of scalars or of equal-length tuples/lists."""
        counts = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
        n = counts[kind]
        flat = []
        for v in values:
            if n == 1:
                flat.append(v)
            else:
                flat.extend(v)
        fmt = {5126: "<f", 5123: "<H", 5125: "<I"}[comp_type]
        data = bytearray()
        for x in flat:
            data += struct.pack(fmt, x if comp_type == 5126 else int(x))

        acc = {"bufferView": self._view(bytes(data), target),
               "componentType": comp_type, "count": len(values), "type": kind}
        if minmax:
            if n == 1:
                acc["min"] = [min(flat)]
                acc["max"] = [max(flat)]
            else:
                acc["min"] = [min(flat[i::n]) for i in range(n)]
                acc["max"] = [max(flat[i::n]) for i in range(n)]
        self.accessors.append(acc)
        return len(self.accessors) - 1



def _material(name, image_uri, base_color):
    pbr = {"metallicFactor": 0.0, "roughnessFactor": 1.0}
    if image_uri:
        pbr["baseColorTexture"] = {"index": 0}
    else:
        pbr["baseColorFactor"] = list(base_color or (0.25, 0.25, 0.28, 1.0))
    return {"name": name + "_mat", "pbrMetallicRoughness": pbr,
            "doubleSided": False}


def export_gltf(path, name, mesh, rig, anims, image_uri=None, base_color=None):
    """`image_uri` None writes a plain untextured material -- all a
    shadow-casting body needs, since shadows come from geometry alone."""
    g = GltfBuilder()

    a_pos = g.accessor(mesh.pos, "VEC3", 5126, target=34962, minmax=True)
    a_nrm = g.accessor(mesh.nrm, "VEC3", 5126, target=34962)
    a_uv = g.accessor(mesh.uv, "VEC2", 5126, target=34962)
    a_joint = g.accessor(mesh.joints, "VEC4", 5123, target=34962)
    a_weight = g.accessor(mesh.weights, "VEC4", 5126, target=34962)
    a_idx = g.accessor(mesh.idx, "SCALAR", 5125, target=34963)
    a_ibm = g.accessor([rig.inverse_bind(i) for i in range(len(rig.names))],
                       "MAT4", 5126)

    # nodes: [0] = skinned mesh, [1..] = bones
    nodes = [{"name": name + "_mesh", "mesh": 0, "skin": 0}]
    bone_node = {i: i + 1 for i in range(len(rig.names))}
    for i, bname in enumerate(rig.names):
        t = rig.local(i)
        node = {"name": bname, "translation": [t[0], t[1], t[2]]}
        kids = [bone_node[c] for c, p in enumerate(rig.parents) if p == i]
        if kids:
            node["children"] = kids
        nodes.append(node)
    roots = [0] + [bone_node[i] for i, p in enumerate(rig.parents) if p < 0]

    animations = []
    for aname, spec in anims.items():
        samplers, channels = [], []
        for bone, prop, times, values in spec["channels"]:
            kind = "VEC4" if prop == "rotation" else "VEC3"
            s_in = g.accessor(times, "SCALAR", 5126, minmax=True)
            s_out = g.accessor(values, kind, 5126)
            samplers.append({"input": s_in, "output": s_out,
                             "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1,
                             "target": {"node": bone_node[bone], "path": prop}})
        animations.append({"name": aname, "samplers": samplers,
                           "channels": channels})

    doc = {
        "asset": {"version": "2.0",
                  "generator": "parnitha tools/gen_animals_new.py"},
        "scene": 0,
        "scenes": [{"name": name, "nodes": roots}],
        "nodes": nodes,
        "meshes": [{
            "name": name,
            "primitives": [{
                "attributes": {"POSITION": a_pos, "NORMAL": a_nrm,
                               "TEXCOORD_0": a_uv, "JOINTS_0": a_joint,
                               "WEIGHTS_0": a_weight},
                "indices": a_idx, "material": 0, "mode": 4,
            }],
        }],
        "skins": [{"name": name + "_skin", "inverseBindMatrices": a_ibm,
                   "skeleton": bone_node[0],
                   "joints": [bone_node[i] for i in range(len(rig.names))]}],
        "materials": [_material(name, image_uri, base_color)],
        "bufferViews": g.views,
        "accessors": g.accessors,
        "buffers": [{"byteLength": len(g.blob),
                     "uri": "data:application/octet-stream;base64,"
                            + base64.b64encode(bytes(g.blob)).decode("ascii")}],
    }
    if image_uri:
        doc["textures"] = [{"sampler": 0, "source": 0}]
        # 9728 NEAREST / 9984 NEAREST_MIPMAP_NEAREST: no filtering, ever
        doc["samplers"] = [{"magFilter": 9728, "minFilter": 9984,
                            "wrapS": 33071, "wrapT": 33071}]
        doc["images"] = [{"uri": image_uri, "mimeType": "image/png"}]
    if animations:
        doc["animations"] = animations

    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1)
    return doc


# ─────────────────────────────────────────────────────────────────────────────
def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def blend_along(a, b, bones):
    """Weights that ramp along segment a->b across a chain of bones.  Repeat a
    bone in the list to hold it flat before the next ramp starts."""
    d = v_sub(b, a)
    L2 = max(v_dot(d, d), 1e-9)
    n = len(bones) - 1

    def fn(p):
        s = clamp01(v_dot(v_sub(p, a), d) / L2) * n
        i = min(int(s), n - 1)
        u = smoothstep(s - i)
        return [(bones[i], 1.0 - u), (bones[i + 1], u)]
    return fn


#  Posing the mesh outside the engine
#
#  Enough forward kinematics and linear blend skinning to answer one question:
#  where does the mesh actually end up in a given pose?  Used to sit the death
#  collapse exactly on the ground rather than guessing at the trigonometry.
# ─────────────────────────────────────────────────────────────────────────────

def quat_to_mat(q):
    x, y, z, w = q
    return ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))


IDENTITY3 = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


def mat_vec(m, v):
    return (m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
            m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
            m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2])


def mat_mul(a, b):
    return tuple(tuple(sum(a[r][k] * b[k][c] for k in range(3))
                       for c in range(3)) for r in range(3))


def xform_mul(a, b):
    """(rotation, translation) composition: a applied after b."""
    return (mat_mul(a[0], b[0]), v_add(mat_vec(a[0], b[1]), a[1]))


def skin_matrices(rig, pose):
    """One (rotation, translation) per bone, ready to multiply bind-pose
    vertices: the bone's global pose times its inverse bind."""
    globals_ = []
    for i, name in enumerate(rig.names):
        p = pose.get(name, {})
        # a translation channel replaces the bone's rest offset, as in glTF
        local = (quat_to_mat(quat_euler(*p["rot"])) if "rot" in p else IDENTITY3,
                 p["pos"] if "pos" in p else rig.local(i))
        parent = rig.parents[i]
        globals_.append(local if parent < 0
                        else xform_mul(globals_[parent], local))
    return [xform_mul(g, (IDENTITY3, v_mul(rig.pos[i], -1.0)))
            for i, g in enumerate(globals_)]


def posed_bounds(mesh, rig, pose):
    """Axis-aligned bounds of the skinned mesh in one pose."""
    mats = skin_matrices(rig, pose)
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for v in range(len(mesh.pos)):
        acc = [0.0, 0.0, 0.0]
        for j, w in zip(mesh.joints[v], mesh.weights[v]):
            if w > 0.0:
                m = mats[j]
                p = v_add(mat_vec(m[0], mesh.pos[v]), m[1])
                acc = [acc[k] + p[k] * w for k in range(3)]
        for k in range(3):
            lo[k] = min(lo[k], acc[k])
            hi[k] = max(hi[k], acc[k])
    return tuple(lo), tuple(hi)


# ─────────────────────────────────────────────────────────────────────────────
def bake(rig, times, poser):
    rots, poss = {}, {}
    for t in times:
        pose = poser(t)
        for name, p in pose.items():
            if "rot" in p:
                rots.setdefault(name, []).append(quat_euler(*p["rot"]))
            if "pos" in p:
                poss.setdefault(name, []).append(list(p["pos"]))
    channels = []
    for name, vals in sorted(rots.items()):
        assert len(vals) == len(times), "poser dropped rot key " + name
        channels.append((rig.idx(name), "rotation", list(times), vals))
    for name, vals in sorted(poss.items()):
        assert len(vals) == len(times), "poser dropped pos key " + name
        channels.append((rig.idx(name), "translation", list(times), vals))
    return channels

