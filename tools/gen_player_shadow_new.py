"""Generates the player's shadow body: a rigged 1937 hunter carrying the rifle.

The player is first-person, so this mesh is never drawn -- it is rendered
shadows-only. That means geometry is the entire product: no atlas, no material
worth speaking of, just a silhouette that reads as a man with a rifle when the
moon throws it across the ground.

Because it is only ever seen as a shadow, the bind pose is the carry pose. The
rifle is skinned rigidly to a `weapon` bone hanging off the right hand, so it
travels with the arms instead of needing its own animation channels.

    models/player/player_shadow_new.gltf    self-contained glTF 2.0

Pipeline:
    1. python tools/gen_player_shadow_new.py
    2. re-import res://models/player in the editor
    3. godot --headless --path . --script res://tools/build_player_shadow_new.gd
    4. godot --headless --path . --script res://tools/verify_player_shadow_new.gd
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from retro_model import *                                      # noqa: F401,F403

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(ROOT, "models", "player")

# Shadow-only: every face samples the same corner of a texture that is never
# loaded, so the atlas layer collapses to this.
FLAT_UV = lambda _region: (0.0, 0.0, 1.0, 1.0)                # noqa: E731
BOX = faces("skin")


# ─────────────────────────────────────────────────────────────────────────────
#  Proportions
#
#  A 1.78 m man in a brimmed hat, standing with the rifle at a ready carry.
#  Points are (x, y, z) in metres; he faces -Z, matching the player body.
# ─────────────────────────────────────────────────────────────────────────────

CFG = {
    # torso chain, bottom to top
    "hips":   (0.0, 0.94, 0.0),
    "spine":  (0.0, 1.12, 0.0),
    "chest":  (0.0, 1.32, 0.0),
    "neck":   (0.0, 1.46, 0.0),
    "head":   (0.0, 1.56, 0.0),

    "pelvis_half": (0.150, 0.10, 0.100),      # half sizes: x, y, z
    "belly_half":  (0.148, 0.10, 0.095),
    "chest_half":  (0.198, 0.115, 0.105),
    "neck_half":   (0.048, 0.05, 0.048),
    "head_half":   (0.088, 0.105, 0.092),
    "hat_brim":    (0.148, 0.013, 0.152),
    "hat_crown":   (0.096, 0.058, 0.098),

    # arms, already bent onto the rifle -- bind pose is the carry pose
    "shoulder_r": (0.215, 1.415, 0.000),
    "elbow_r":    (0.272, 1.198, -0.022),
    "hand_r":     (0.160, 1.085, -0.185),
    "shoulder_l": (-0.215, 1.415, 0.000),
    "elbow_l":    (-0.228, 1.212, -0.142),
    "hand_l":     (-0.020, 1.140, -0.520),
    "arm_r_top":  0.052,
    "arm_r_mid":  0.043,
    "arm_r_low":  0.036,
    "hand_half":  (0.038, 0.048, 0.040),

    # legs
    "hip_x":    0.098,
    "knee":     (0.098, 0.500, 0.012),
    "ankle":    (0.098, 0.085, 0.000),
    "thigh_top": 0.078,
    "thigh_low": 0.060,
    "shin_low":  0.048,
    "foot_half": (0.052, 0.043, 0.125),
    "foot_z":    -0.055,

    # rifle: butt by the right hip, muzzle forward and slightly left
    "butt":   (0.235, 1.040, 0.070),
    "muzzle": (-0.095, 1.200, -0.905),
    "stock_half":    (0.030, 0.052),
    "receiver_half": (0.026, 0.040),
    "barrel_half":   (0.014, 0.016),
}


def build_body(cfg):
    """Returns (mesh, rig). One prism per body segment, hard-edged throughout."""
    mesh, rig = Mesh(FLAT_UV), Rig()

    rig.add("root", None, (0.0, 0.0, 0.0))
    rig.add("hips", "root", cfg["hips"])
    rig.add("spine", "hips", cfg["spine"])
    rig.add("chest", "spine", cfg["chest"])
    rig.add("neck", "chest", cfg["neck"])
    rig.add("head", "neck", cfg["head"])
    for side in ("r", "l"):
        rig.add("arm_%s_upper" % side, "chest", cfg["shoulder_" + side])
        rig.add("arm_%s_lower" % side, "arm_%s_upper" % side, cfg["elbow_" + side])
        rig.add("hand_%s" % side, "arm_%s_lower" % side, cfg["hand_" + side])
    rig.add("weapon", "hand_r", cfg["hand_r"])
    for side, sx in (("r", 1.0), ("l", -1.0)):
        hip = (sx * cfg["hip_x"], cfg["hips"][1] - 0.02, 0.0)
        knee = (sx * cfg["knee"][0], cfg["knee"][1], cfg["knee"][2])
        ankle = (sx * cfg["ankle"][0], cfg["ankle"][1], cfg["ankle"][2])
        rig.add("leg_%s_upper" % side, "hips", hip)
        rig.add("leg_%s_lower" % side, "leg_%s_upper" % side, knee)
        rig.add("foot_%s" % side, "leg_%s_lower" % side, ankle)

    b = {n: rig.idx(n) for n in rig.names}

    # ── torso: three blocks, weights ramping up the spine ──────────────────
    def slab(lo, hi, half_lo, half_hi, weight_fn):
        mesh.add_prism(lo, hi, (half_lo[0], half_lo[2]), (half_hi[0], half_hi[2]),
                       BOX, weight_fn)

    pelvis_lo = (0.0, cfg["hips"][1] - cfg["pelvis_half"][1], 0.0)
    belly = (0.0, cfg["spine"][1], 0.0)
    chest_lo = (0.0, cfg["chest"][1] - cfg["chest_half"][1], 0.0)
    chest_hi = (0.0, cfg["chest"][1] + cfg["chest_half"][1], 0.0)

    def flat(half):
        return (half[0], half[2])

    w_torso = blend_along(pelvis_lo, chest_lo,
                          [b["hips"], b["hips"], b["spine"], b["chest"]])
    mesh.add_tube([(pelvis_lo, flat(cfg["pelvis_half"])),
                   (belly, flat(cfg["belly_half"])),
                   (chest_lo, flat(cfg["chest_half"])),
                   (chest_hi, flat(cfg["chest_half"]))],
                  [BOX, BOX, BOX], w_torso, cap_a="skin", cap_b="skin")

    # ── neck and head ──────────────────────────────────────────────────────
    neck_lo = (0.0, cfg["neck"][1] - 0.05, 0.0)
    neck_hi = (0.0, cfg["neck"][1] + 0.05, 0.0)
    hh = cfg["head_half"]
    head_lo = (0.0, cfg["head"][1] - hh[1], 0.0)
    head_hi = (0.0, cfg["head"][1] + hh[1], 0.0)
    w_neck = blend_along(neck_lo, neck_hi, [b["chest"], b["neck"], b["head"]])

    def w_neck_head(p):
        return rigid(b["head"])(p) if p[1] >= head_lo[1] else w_neck(p)

    mesh.add_tube([(neck_lo, (cfg["neck_half"][0], cfg["neck_half"][2])),
                   (neck_hi, (cfg["neck_half"][0], cfg["neck_half"][2])),
                   (head_lo, (hh[0], hh[2])),
                   (head_hi, (hh[0] * 0.94, hh[2] * 0.94))],
                  [BOX, BOX, BOX], w_neck_head, cap_a="skin", cap_b="skin")

    # The hat is the whole point: a bare head reads as a post, a brim reads as
    # a person at fifty metres of shadow.
    brim = cfg["hat_brim"]
    crown = cfg["hat_crown"]
    brim_lo = (0.0, head_hi[1] - 0.008, -0.012)
    brim_hi = (0.0, head_hi[1] + brim[1] * 2.0, -0.012)
    mesh.add_prism(brim_lo, brim_hi, (brim[0], brim[2]), (brim[0], brim[2]),
                   BOX, rigid(b["head"]))
    mesh.add_prism(brim_hi, (0.0, brim_hi[1] + crown[1] * 2.0, 0.0),
                   (crown[0], crown[2]), (crown[0] * 0.92, crown[2] * 0.92),
                   BOX, rigid(b["head"]))

    # ── arms ───────────────────────────────────────────────────────────────
    for side in ("r", "l"):
        sh = cfg["shoulder_" + side]
        el = cfg["elbow_" + side]
        ha = cfg["hand_" + side]
        up = b["arm_%s_upper" % side]
        lo = b["arm_%s_lower" % side]
        hd = b["hand_%s" % side]
        r0, r1, r2 = cfg["arm_r_top"], cfg["arm_r_mid"], cfg["arm_r_low"]
        fist = cfg["hand_half"]
        tip = v_add(ha, v_mul(v_norm(v_sub(ha, el)), fist[1] * 2.0))

        def w_arm(p, _sh=sh, _el=el, _ha=ha, _up=up, _lo=lo, _hd=hd):
            return (blend_along(_el, _ha, [_lo, _lo, _hd])(p)
                    if v_dot(v_sub(p, _el), v_sub(_ha, _el)) > 0.0
                    else blend_along(_sh, _el, [_up, _up, _lo])(p))

        mesh.add_tube([(sh, (r0, r0)), (el, (r1, r1)), (ha, (r2, r2)),
                       (tip, (fist[0] * 0.9, fist[2] * 0.9))],
                      [BOX, BOX, BOX], w_arm, cap_a="skin", cap_b="skin")

    # ── legs ───────────────────────────────────────────────────────────────
    for side, sx in (("r", 1.0), ("l", -1.0)):
        hip = (sx * cfg["hip_x"], cfg["hips"][1] - 0.02, 0.0)
        knee = (sx * cfg["knee"][0], cfg["knee"][1], cfg["knee"][2])
        ankle = (sx * cfg["ankle"][0], cfg["ankle"][1], cfg["ankle"][2])
        up = b["leg_%s_upper" % side]
        lo = b["leg_%s_lower" % side]
        ft = b["foot_%s" % side]
        t0, t1, s1 = cfg["thigh_top"], cfg["thigh_low"], cfg["shin_low"]
        def w_leg(p, _hip=hip, _knee=knee, _ankle=ankle, _up=up, _lo=lo, _ft=ft):
            return (blend_along(_knee, _ankle, [_lo, _lo, _ft])(p)
                    if p[1] <= _knee[1]
                    else blend_along(_hip, _knee, [_up, _up, _lo])(p))

        mesh.add_tube([(hip, (t0, t0)), (knee, (t1, t1)), (ankle, (s1, s1))],
                      [BOX, BOX], w_leg, cap_a="skin", cap_b="skin")
        fh = cfg["foot_half"]
        heel = (sx * cfg["ankle"][0], fh[1], cfg["foot_z"] + fh[2])
        toe = (sx * cfg["ankle"][0], fh[1] * 0.8, cfg["foot_z"] - fh[2])
        mesh.add_prism(heel, toe, (fh[0], fh[1]), (fh[0] * 0.9, fh[1] * 0.8),
                       BOX, rigid(ft))

    # ── the rifle, rigid to the weapon bone under the right hand ───────────
    butt = cfg["butt"]
    muzzle = cfg["muzzle"]
    axis = v_norm(v_sub(muzzle, butt))
    gun = rigid(b["weapon"])

    def along(t):
        return v_add(butt, v_mul(v_sub(muzzle, butt), t))

    st = cfg["stock_half"]
    rc = cfg["receiver_half"]
    bl = cfg["barrel_half"]
    mesh.add_prism(butt, along(0.30), (st[0], st[1]), (rc[0], rc[1]), BOX, gun)
    mesh.add_prism(along(0.30), along(0.46), (rc[0], rc[1]),
                   (rc[0] * 0.95, rc[1] * 0.9), BOX, gun)
    mesh.add_prism(along(0.46), muzzle, (bl[0] * 1.4, bl[1] * 1.4),
                   (bl[0], bl[1]), BOX, gun)
    # bolt handle, sticking out to the right -- a small but very legible notch
    bolt = along(0.40)
    mesh.add_prism(bolt, v_add(bolt, (0.075, -0.020, 0.0)),
                   (0.011, 0.011), (0.016, 0.016), BOX, gun)

    return mesh, rig


# ─────────────────────────────────────────────────────────────────────────────
#  Clips
#
#  Bind pose is the carry pose, so every clip is a small delta off it. Rotation
#  about +X swings a downward-pointing bone's tip forward (-Z).
# ─────────────────────────────────────────────────────────────────────────────

def _leg(side, theta, swing, flex):
    """One leg at gait phase `theta`. Human knees fold backwards, so the shin
    rotation is negative, and the ankle counter-rotates to keep the sole flat."""
    upper = swing * math.sin(theta)
    lower = -flex * max(0.0, math.cos(theta))
    return {
        "leg_%s_upper" % side: {"rot": (upper, 0.0, 0.0)},
        "leg_%s_lower" % side: {"rot": (lower, 0.0, 0.0)},
        "foot_%s" % side: {"rot": (-(upper + lower) * 0.45, 0.0, 0.0)},
    }


def _stride_poser(length, swing, flex, bob, lean, twist, arm):
    """Shared walk/run construction -- only the amplitudes differ."""
    def poser(t):
        th = 2.0 * math.pi * t / length
        pose = {}
        pose.update(_leg("l", th, swing, flex))
        pose.update(_leg("r", th + math.pi, swing, flex))
        # highest as the legs pass under the body, twice a cycle
        pose["root"] = {"pos": (0.0, bob * math.cos(2.0 * th), 0.0),
                        "rot": (0.0, 0.0, 0.0)}
        pose["hips"] = {"rot": (0.0, twist * math.sin(th),
                                0.035 * math.sin(th))}
        pose["spine"] = {"rot": (lean * 0.4, -twist * 0.5 * math.sin(th), 0.0)}
        pose["chest"] = {"rot": (lean * 0.6, -twist * 0.8 * math.sin(th), 0.0)}
        pose["neck"] = {"rot": (-lean * 0.7, 0.0, 0.0)}
        pose["head"] = {"rot": (-lean * 0.3, 0.0, 0.0)}
        # hands stay on the rifle: the arms brace against the stride rather
        # than swinging with it
        pose["arm_r_upper"] = {"rot": (arm * math.sin(th), 0.0, 0.0)}
        pose["arm_l_upper"] = {"rot": (arm * math.sin(th + math.pi), 0.0, 0.0)}
        pose["arm_r_lower"] = {"rot": (-arm * 0.5 * math.sin(th), 0.0, 0.0)}
        pose["arm_l_lower"] = {"rot": (-arm * 0.5 * math.sin(th + math.pi),
                                       0.0, 0.0)}
        return pose
    return poser, length


def walk_poser(_cfg):
    return _stride_poser(1.00, swing=0.44, flex=0.90, bob=0.030,
                         lean=-0.05, twist=0.11, arm=0.09)


def run_poser(_cfg):
    return _stride_poser(0.68, swing=0.74, flex=1.35, bob=0.055,
                         lean=-0.30, twist=0.17, arm=0.16)


def idle_poser(_cfg):
    L = 3.4

    def poser(t):
        u = t / L
        breath = math.sin(2.0 * math.pi * u)
        sway = math.sin(2.0 * math.pi * u * 0.5)
        pose = {}
        for side in ("l", "r"):
            pose.update(_leg(side, 0.0, 0.0, 0.0))
        pose["root"] = {"pos": (0.0, 0.005 * breath, 0.0), "rot": (0, 0, 0)}
        pose["hips"] = {"rot": (0.0, 0.02 * sway, 0.012 * sway)}
        pose["spine"] = {"rot": (0.010 * breath, -0.015 * sway, 0.0)}
        pose["chest"] = {"rot": (0.020 * breath, -0.02 * sway, 0.0)}
        pose["neck"] = {"rot": (-0.015 * breath, 0.03 * sway, 0.0)}
        pose["head"] = {"rot": (0.0, 0.06 * sway, 0.0)}
        # the rifle drifts a little in the hands, as a carried weight does
        pose["arm_r_upper"] = {"rot": (0.018 * breath, 0.0, 0.0)}
        pose["arm_l_upper"] = {"rot": (0.014 * breath, 0.0, 0.0)}
        pose["weapon"] = {"rot": (0.03 * breath, 0.02 * sway, 0.0)}
        return pose
    return poser, L


def aim_poser(_cfg):
    """Shouldered. The read from a distance is the raised right elbow and the
    rifle gone horizontal, so those are what the pose commits to."""
    L = 2.6

    def poser(t):
        u = t / L
        breath = math.sin(2.0 * math.pi * u)
        pose = {}
        for side in ("l", "r"):
            pose.update(_leg(side, 0.0, 0.0, 0.0))
        # slight crouch into the shot, weight forward
        pose["root"] = {"pos": (0.0, -0.020 + 0.004 * breath, 0.0),
                        "rot": (0.0, 0.0, 0.0)}
        pose["leg_r_upper"] = {"rot": (0.10, 0.0, 0.0)}
        pose["leg_r_lower"] = {"rot": (-0.16, 0.0, 0.0)}
        pose["leg_l_upper"] = {"rot": (-0.08, 0.0, 0.0)}
        pose["leg_l_lower"] = {"rot": (-0.10, 0.0, 0.0)}
        pose["hips"] = {"rot": (0.0, -0.22, 0.0)}
        pose["spine"] = {"rot": (-0.06, -0.14, 0.0)}
        pose["chest"] = {"rot": (-0.10 + 0.012 * breath, -0.12, 0.0)}
        pose["neck"] = {"rot": (0.16, 0.10, 0.0)}
        pose["head"] = {"rot": (0.10, 0.14, 0.0)}
        # right elbow up and out, hand drawn back to the shoulder
        pose["arm_r_upper"] = {"rot": (-0.30, -0.20, -0.85)}
        pose["arm_r_lower"] = {"rot": (0.15, 0.55, 0.30)}
        pose["arm_l_upper"] = {"rot": (-0.28, 0.10, 0.30)}
        pose["arm_l_lower"] = {"rot": (0.10, -0.15, 0.0)}
        pose["weapon"] = {"rot": (0.22 + 0.010 * breath, 0.30, 0.55)}
        return pose
    return poser, L


CLIPS = (("idle", idle_poser, 17), ("walk", walk_poser, 17),
         ("run", run_poser, 17), ("aim", aim_poser, 13))


def make_animations(rig, cfg):
    anims = {}
    for name, factory, keys in CLIPS:
        poser, L = factory(cfg)
        times = [round(L * i / (keys - 1), 5) for i in range(keys)]
        anims[name] = {"length": L, "channels": bake(rig, times, poser)}
    return anims


def main():
    os.makedirs(MODEL_DIR, exist_ok=True)
    mesh, rig = build_body(CFG)
    anims = make_animations(rig, CFG)
    export_gltf(os.path.join(MODEL_DIR, "player_shadow_new.gltf"),
                "player_shadow_new", mesh, rig, anims)

    lo, hi = posed_bounds(mesh, rig, {})
    print("player_shadow_new  %d tris  %d verts  %d bones  %d clips"
          % (mesh.tris, len(mesh.pos), len(rig.names), len(CLIPS)))
    print("  standing %.2f m tall, %.2f m wide, %.2f m deep"
          % (hi[1] - lo[1], hi[0] - lo[0], hi[2] - lo[2]))
    print("  feet at y=%.3f" % lo[1])


if __name__ == "__main__":
    main()
