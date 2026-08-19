"""Structural audit of the generated animal glTFs and their atlases.

Reads back what tools/gen_animals_new.py wrote and checks it the way an
importer would: attribute counts, UVs landing inside real atlas tiles, skin
weights that sum to one, valid joint indices, unit quaternions, winding, and
the three required animations.  Exits non-zero on any failure.
"""

import base64
import json
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(ROOT, "models", "animals")
TEX_DIR = os.path.join(ROOT, "textures", "animals")

sys.dont_write_bytecode = True   # no __pycache__ inside the Godot project
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_animals_new import REGIONS, TEX          # noqa: E402  (shared truth)

REQUIRED_ANIMS = ["idle", "walk", "death"]
NAMES = ["boar_new", "baby_boar_new", "deer_new", "baby_deer_new",
         "sheep_new", "baby_sheep_new"]

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

FAILURES = []


def check(cond, model, msg):
    if not cond:
        FAILURES.append("%s: %s" % (model, msg))
    return cond


def read_accessor(doc, blob, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    fmt, size = {5126: ("<f", 4), 5123: ("<H", 2),
                 5125: ("<I", 4)}[acc["componentType"]]
    off = view.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        vals = []
        for c in range(n):
            vals.append(struct.unpack_from(fmt, blob, off + (i * n + c) * size)[0])
        out.append(vals[0] if n == 1 else tuple(vals))
    return out


def load_gltf(path):
    doc = json.load(open(path, encoding="utf-8"))
    blob = base64.b64decode(doc["buffers"][0]["uri"].split(",", 1)[1])
    return doc, blob


def region_of(u, v):
    """Which atlas tile does this UV land in?  None means it is off-sheet."""
    px, py = u * TEX, v * TEX
    for name, (x, y, w, h) in REGIONS.items():
        if x <= px <= x + w and y <= py <= y + h:
            return name
    return None


def verify_png(model, path):
    if not check(os.path.exists(path), model, "atlas missing: " + path):
        return
    data = open(path, "rb").read()
    check(data[:8] == PNG_MAGIC, model, "not a PNG")
    w, h, depth, ctype = struct.unpack(">IIBB", data[16:26])
    check((w, h) == (TEX, TEX), model,
          "atlas is %dx%d, expected %d square" % (w, h, TEX))
    check(depth == 8 and ctype == 2, model, "atlas is not 8-bit RGB")

    idat = b""
    pos = 8
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        if data[pos + 4:pos + 8] == b"IDAT":
            idat += data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * 3 + 1
    if not check(len(raw) == stride * h, model, "atlas pixel data truncated"):
        return
    # every channel must be quantised to 5 bits -- the retro colour budget
    bad = sum(1 for i in range(h)
              for b in raw[i * stride + 1:(i + 1) * stride] if b & 0x07)
    check(not bad, model, "%d samples are not 15-bit quantised" % bad)
    # and the sheet must not have come out one flat colour
    swatch = {tuple(raw[i * stride + 1 + j * 3: i * stride + 4 + j * 3])
              for i in range(0, h, 7) for j in range(0, w, 7)}
    check(len(swatch) > 24, model, "atlas looks flat (%d colours)" % len(swatch))


def verify_model(name):
    path = os.path.join(MODEL_DIR, name + ".gltf")
    if not check(os.path.exists(path), name, "gltf missing"):
        return
    doc, blob = load_gltf(path)

    check(doc["asset"]["version"] == "2.0", name, "not glTF 2.0")
    prim = doc["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]
    for a in ("POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"):
        check(a in attrs, name, "missing attribute " + a)
    check("indices" in prim, name, "mesh is not indexed")
    check(prim.get("material") == 0, name, "primitive has no material")

    pos = read_accessor(doc, blob, attrs["POSITION"])
    nrm = read_accessor(doc, blob, attrs["NORMAL"])
    uv = read_accessor(doc, blob, attrs["TEXCOORD_0"])
    joints = read_accessor(doc, blob, attrs["JOINTS_0"])
    weights = read_accessor(doc, blob, attrs["WEIGHTS_0"])
    idx = read_accessor(doc, blob, prim["indices"])

    n = len(pos)
    check(len(nrm) == n and len(uv) == n and len(joints) == n
          and len(weights) == n, name, "attribute streams disagree on length")
    check(len(idx) % 3 == 0, name, "index count is not a multiple of 3")
    check(max(idx) < n, name, "index out of range")

    # ── UVs must sit inside a real atlas tile ──────────────────────────────
    off_sheet = sum(1 for u, v in uv
                    if not (0.0 <= u <= 1.0 and 0.0 <= v <= 1.0))
    check(not off_sheet, name, "%d UVs outside 0..1" % off_sheet)
    stray = sum(1 for u, v in uv if region_of(u, v) is None)
    check(not stray, name, "%d UVs land between atlas tiles" % stray)
    used = {region_of(u, v) for u, v in uv}
    check(len(used) >= 8, name,
          "only %d atlas tiles used: %s" % (len(used), sorted(used)))
    check(len({(round(u, 4), round(v, 4)) for u, v in uv}) > 4, name,
          "UVs are degenerate (every corner identical)")

    # ── skin weights ───────────────────────────────────────────────────────
    n_joints = len(doc["skins"][0]["joints"])
    check("inverseBindMatrices" in doc["skins"][0], name, "no bind matrices")
    ibm = read_accessor(doc, blob, doc["skins"][0]["inverseBindMatrices"])
    check(len(ibm) == n_joints, name, "bind matrix count != joint count")

    bad_sum = sum(1 for w in weights if abs(sum(w) - 1.0) > 1e-4)
    check(not bad_sum, name,
          "%d vertices whose weights do not sum to 1" % bad_sum)
    unweighted = sum(1 for w in weights if max(w) <= 0.0)
    check(not unweighted, name, "%d vertices with no bone influence" % unweighted)
    bad_j = sum(1 for i, js in enumerate(joints)
                if any(j >= n_joints for j, w in zip(js, weights[i]) if w > 0))
    check(not bad_j, name,
          "%d vertices reference a joint that does not exist" % bad_j)

    influence = [0] * n_joints
    for js, ws in zip(joints, weights):
        for j, w in zip(js, ws):
            if w > 0.001:
                influence[j] += 1
    bone_name = [doc["nodes"][j]["name"] for j in doc["skins"][0]["joints"]]
    # "root" is a control bone -- it moves the whole animal and is allowed to
    # own no vertices.  Every other bone must actually deform something.
    dead = [bone_name[j] for j in range(n_joints)
            if influence[j] == 0 and bone_name[j] != "root"]
    blended = sum(1 for ws in weights if sorted(ws)[-1] < 0.999)
    check(not dead, name, "bones carry no weight and deform nothing: %s" % dead)
    check(blended > 20, name,
          "only %d vertices blend two bones -- the rig is fully rigid" % blended)

    # ── winding / geometry sanity ──────────────────────────────────────────
    vol = 0.0
    degenerate = flipped = 0
    for t in range(0, len(idx), 3):
        a, b, c = pos[idx[t]], pos[idx[t + 1]], pos[idx[t + 2]]
        ab = [b[i] - a[i] for i in range(3)]
        ac = [c[i] - a[i] for i in range(3)]
        cr = (ab[1] * ac[2] - ab[2] * ac[1],
              ab[2] * ac[0] - ab[0] * ac[2],
              ab[0] * ac[1] - ab[1] * ac[0])
        area = (cr[0] ** 2 + cr[1] ** 2 + cr[2] ** 2) ** 0.5
        if area < 1e-9:
            degenerate += 1
            continue
        vn = nrm[idx[t]]
        if sum(cr[i] / area * vn[i] for i in range(3)) < 0.95:
            flipped += 1
        vol += (a[0] * (b[1] * c[2] - b[2] * c[1])
                - a[1] * (b[0] * c[2] - b[2] * c[0])
                + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
    # ── watertightness ─────────────────────────────────────────────────────
    # Every edge of a closed shell is shared by exactly two triangles. The only
    # deliberately open surfaces are the two single-quad eyes, so anything past
    # a handful of loose edges means a body has been left with a hole in it.
    edge_use = {}
    for t in range(0, len(idx), 3):
        tri = [idx[t], idx[t + 1], idx[t + 2]]
        for k in range(3):
            a = tuple(round(c, 5) for c in pos[tri[k]])
            b = tuple(round(c, 5) for c in pos[tri[(k + 1) % 3]])
            key = (a, b) if a <= b else (b, a)
            edge_use[key] = edge_use.get(key, 0) + 1
    loose = sum(1 for v in edge_use.values() if v == 1)
    check(loose <= 8, name,
          "%d edges belong to only one triangle -- the surface is open" % loose)

    check(degenerate == 0, name, "%d degenerate triangles" % degenerate)
    check(flipped == 0, name,
          "%d triangles whose winding fights their normal" % flipped)
    check(vol > 0.0, name, "mesh is wound inside-out (signed volume %.4f)" % vol)

    # ── animations ─────────────────────────────────────────────────────────
    anims = doc.get("animations", [])
    got = [a["name"] for a in anims]
    check(got == REQUIRED_ANIMS, name,
          "animations are %s, expected %s" % (got, REQUIRED_ANIMS))
    joint_nodes = set(doc["skins"][0]["joints"])
    for anim in anims:
        moved = set()
        for ch in anim["channels"]:
            node = ch["target"]["node"]
            check(node in joint_nodes, name,
                  "%s drives node %d, which is not a bone" % (anim["name"], node))
            samp = anim["samplers"][ch["sampler"]]
            times = read_accessor(doc, blob, samp["input"])
            vals = read_accessor(doc, blob, samp["output"])
            check(len(times) == len(vals), name,
                  "%s channel has %d times but %d values"
                  % (anim["name"], len(times), len(vals)))
            check(all(times[i] < times[i + 1] for i in range(len(times) - 1)),
                  name, "%s keyframe times are not increasing" % anim["name"])
            if ch["target"]["path"] == "rotation":
                bad = sum(1 for q in vals
                          if abs(sum(x * x for x in q) - 1.0) > 1e-4)
                check(not bad, name,
                      "%s has %d non-unit quaternions" % (anim["name"], bad))
            spread = max(max(abs(v[k] - vals[0][k]) for k in range(len(v)))
                         for v in vals)
            if spread > 1e-4:
                moved.add(doc["nodes"][node]["name"])
        check(len(moved) >= 6, name, "%s actually moves only %d bones: %s"
              % (anim["name"], len(moved), sorted(moved)))

    img = doc["images"][0]["uri"]
    check(os.path.exists(os.path.normpath(os.path.join(MODEL_DIR, img))), name,
          "image uri does not resolve: " + img)
    check(doc["samplers"][0]["magFilter"] == 9728, name, "sampler is not NEAREST")

    print("  %-16s %4d tris %4d verts %2d bones %3d blended-verts "
          "%2d tiles vol=%.3f anims=%s"
          % (name, len(idx) // 3, n, n_joints, blended, len(used), vol,
             ",".join(got)))


def main():
    print("verifying generated animals")
    for name in NAMES:
        verify_model(name)
        verify_png(name, os.path.join(
            TEX_DIR, name.replace("_new", "_atlas_new") + ".png"))
    if FAILURES:
        print("\nFAILED (%d):" % len(FAILURES))
        for f in FAILURES:
            print("  -", f)
        sys.exit(1)
    print("\nall %d models pass structural verification" % len(NAMES))


if __name__ == "__main__":
    main()
