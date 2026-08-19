# Generates res://scenes/levels/Level3.tscn -- the Sanatorium interior, 3 floors.
#
# Layout, per floor: one long central corridor with four ward rooms on each
# side, and a stair hall at the south end. The stair is a single straight
# flight rising north through an opening in the slab above. The player starts
# on the tarp at the foot of that stair; 56m away at the far end of the ground
# corridor is the main entrance door, lit from outside and permanently shut.
#
# Structure that must stop the player is CSGBox3D with collision. Everything
# else -- dado bands, handrails, stair treads, rubble, window frames -- is a
# MeshInstance3D sharing one unit BoxMesh, which is far cheaper to build and
# draw. Architectural materials use world triplanar mapping so texel density is
# identical on every surface in the building regardless of box size.
import math
import random

rng = random.Random(19391123)

# -- Dimensions --------------------------------------------------------------
FLOORS = 3
CEIL_H = 3.4                     # clear interior height
SLAB = 0.4
FLOOR_H = CEIL_H + SLAB          # 3.8 floor to floor
FLOOR_Y = [i * FLOOR_H for i in range(FLOORS)]
ROOF_Y = FLOOR_Y[-1] + CEIL_H

T = 0.35                         # wall thickness
DADO_H = 1.15                    # painted lower band
RAIL_Y = 0.92                    # corridor handrail height
DOOR_W = 2.4
DOOR_H = 2.4

COR_HW = 3.0                     # corridor half-width
WALL_X = COR_HW + T / 2          # 3.175
ROOM_X = 16.0                    # room outer face
OUT_X = ROOM_X + T / 2           # 16.175
EDGE_X = OUT_X + T / 2           # 16.35

COR_Z0, COR_Z1 = 0.0, 56.0
BANDS = [(0.0, 14.0), (14.0, 28.0), (28.0, 42.0), (42.0, 56.0)]
DOORS = [(a + b) / 2 for a, b in BANDS]      # 7, 21, 35, 49
DIVS = [14.0, 28.0, 42.0]
HALL_WIN_Z = -9.0                # the lobby gets one window per side too

# Windows are real holes in the outer wall, not lit panels, so their size has
# to be known before the walls are built.
WIN_W = 2.6
WIN_SILL = 0.95
WIN_HEAD = 2.75
DOOR_HALL_W = 3.4          # the front doors, centred on the spawn line
DOOR_HALL_X = -2.0

HALL_Z0 = -18.0
EDGE_Z0 = HALL_Z0 - T            # -18.35
EDGE_Z1 = COR_Z1 + T             # 56.35

# Stair: one straight flight, west face open to the hall.
ST_X0, ST_X1 = 4.0, 8.0
ST_ZB, ST_ZT = -16.0, -2.0
ST_STEPS = 11
OP_X0, OP_X1 = 3.5, 8.5          # opening in the slab above
OP_Z0, OP_Z1 = -16.5, -2.0

TARP = (-2.0, -0.048, -11.0)

nodes = []


def _yaw(rot_y, sx=1.0, sy=1.0, sz=1.0):
    # Transform3D's twelve-float constructor takes the basis by ROWS, not by
    # the transformed axes. Emitting columns here silently transposes every
    # rotation -- harmless on a yawed box, but it inverted the stair ramp into
    # a descent. Build the rows of (rotation * scale) explicitly.
    c, s = math.cos(rot_y), math.sin(rot_y)
    return (c * sx, 0.0, s * sz, 0.0, sy, 0.0, -s * sx, 0.0, c * sz)


def csg(name, parent, cx, cy, cz, sx, sy, sz, mat, rot_y=0.0, collide=True):
    b = _yaw(rot_y)
    out = ['[node name="%s" type="CSGBox3D" parent="%s"]' % (name, parent),
           "transform = Transform3D(%.6g, %g, %.6g, %g, %g, %g, %.6g, %g, %.6g, %.4g, %.4g, %.4g)"
           % (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], cx, cy, cz)]
    if collide:
        out.append("use_collision = true")
    out.append("size = Vector3(%.4g, %.4g, %.4g)" % (sx, sy, sz))
    out.append('material = SubResource("%s")' % mat)
    nodes.append("\n".join(out))


def deco(name, parent, cx, cy, cz, sx, sy, sz, mat, rot_y=0.0, shadows=True):
    """Non-colliding detail: one shared unit BoxMesh, scaled by the transform."""
    b = _yaw(rot_y, sx, sy, sz)
    out = ['[node name="%s" type="MeshInstance3D" parent="%s"]' % (name, parent),
           "transform = Transform3D(%.6g, %g, %.6g, %g, %.6g, %g, %.6g, %g, %.6g, %.4g, %.4g, %.4g)"
           % (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], cx, cy, cz)]
    if not shadows:
        out.append("cast_shadow = 0")
    out.append('mesh = SubResource("BoxMesh_unit")')
    out.append('material_override = SubResource("%s")' % mat)
    nodes.append("\n".join(out))


def box(name, parent, x0, x1, y0, y1, z0, z1, mat, collide=True):
    csg(name, parent, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2,
        x1 - x0, y1 - y0, z1 - z0, mat, collide=collide)


def panel(name, parent, x0, x1, y0, y1, z0, z1, mat, shadows=True):
    deco(name, parent, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2,
         x1 - x0, y1 - y0, z1 - z0, mat, shadows=shadows)


def ramp(name, parent, xc, w, z0, y0, z1, y1, thick, mat, collide=True):
    """Box whose top face runs from (z0,y0) to (z1,y1). Rises toward +z."""
    dz, dy = z1 - z0, y1 - y0
    th = math.atan2(dy, dz)
    length = math.hypot(dz, dy)
    c, s = math.cos(th), math.sin(th)
    # Local +Y is the surface normal; step down half a thickness along it.
    cy = (y0 + y1) / 2 - thick / 2 * c
    cz = (z0 + z1) / 2 + thick / 2 * s
    # Rows again: an X-rotation whose local +Z climbs toward +z.
    out = ['[node name="%s" type="CSGBox3D" parent="%s"]' % (name, parent),
           "transform = Transform3D(1, 0, 0, 0, %.6g, %.6g, 0, %.6g, %.6g, %.4g, %.4g, %.4g)"
           % (c, s, -s, c, xc, cy, cz)]
    if collide:
        out.append("use_collision = true")
    out.append("size = Vector3(%.4g, %.4g, %.4g)" % (w, thick, length))
    out.append('material = SubResource("%s")' % mat)
    nodes.append("\n".join(out))


def omni(name, parent, x, y, z, color, energy, rng_m, flicker=False, shadows=True):
    out = ['[node name="%s" type="OmniLight3D" parent="%s"]' % (name, parent),
           "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4g, %.4g, %.4g)" % (x, y, z),
           "light_color = Color(%g, %g, %g, 1)" % color,
           "light_energy = %g" % energy,
           "omni_range = %g" % rng_m]
    if not shadows:
        out.append("shadow_enabled = false")
    if flicker:
        out.append('script = ExtResource("s_flicker")')
    nodes.append("\n".join(out))


def spot(name, parent, x, y, z, yaw, color, energy, rng_m, angle):
    c, s = math.cos(yaw), math.sin(yaw)
    nodes.append("\n".join([
        '[node name="%s" type="SpotLight3D" parent="%s"]' % (name, parent),
        "transform = Transform3D(%.6g, 0, %.6g, 0, 1, 0, %.6g, 0, %.6g, %.4g, %.4g, %.4g)"
        % (c, s, -s, c, x, y, z),
        "light_color = Color(%g, %g, %g, 1)" % color,
        "light_energy = %g" % energy,
        "shadow_enabled = false",
        "spot_range = %g" % rng_m,
        "spot_angle = %g" % angle]))


def dress_window_z(tag, Y, outer, sign, wz, radiator=True):
    """Joinery and glazing for one opening in a wall that runs along Z."""
    lo, hi = sorted((outer - sign * 0.05, outer))
    panel("WinJambA_%s" % tag, "Trim", lo, hi, Y + WIN_SILL, Y + WIN_HEAD,
          wz - WIN_W / 2 - 0.09, wz - WIN_W / 2 + 0.03, "Mat_wood", shadows=False)
    panel("WinJambB_%s" % tag, "Trim", lo, hi, Y + WIN_SILL, Y + WIN_HEAD,
          wz + WIN_W / 2 - 0.03, wz + WIN_W / 2 + 0.09, "Mat_wood", shadows=False)
    panel("WinHead_%s" % tag, "Trim", lo, hi, Y + WIN_HEAD - 0.06, Y + WIN_HEAD + 0.06,
          wz - WIN_W / 2 - 0.09, wz + WIN_W / 2 + 0.09, "Mat_wood", shadows=False)
    lo, hi = sorted((outer - sign * 0.26, outer))
    panel("WinSill_%s" % tag, "Trim", lo, hi, Y + WIN_SILL - 0.07, Y + WIN_SILL,
          wz - WIN_W / 2 - 0.12, wz + WIN_W / 2 + 0.12, "Mat_wood")
    lo, hi = sorted((outer - sign * 0.09, outer - sign * 0.04))
    panel("WinMullV_%s" % tag, "Trim", lo, hi, Y + WIN_SILL, Y + WIN_HEAD,
          wz - 0.05, wz + 0.05, "Mat_wood", shadows=False)
    panel("WinMullH_%s" % tag, "Trim", lo, hi, Y + 1.83, Y + 1.91,
          wz - WIN_W / 2, wz + WIN_W / 2, "Mat_wood", shadows=False)
    # Dirty grey glazing, set deeper in the reveal than the mullions. Rough and
    # refractive, so the treeline outside goes soft rather than merely dimmer.
    lo, hi = sorted((outer - sign * 0.185, outer - sign * 0.165))
    panel("WinGlass_%s" % tag, "Trim", lo, hi, Y + WIN_SILL + 0.01, Y + WIN_HEAD - 0.01,
          wz - WIN_W / 2 + 0.01, wz + WIN_W / 2 - 0.01, "Mat_glass", shadows=False)
    if radiator:
        lo, hi = sorted((outer - sign * 0.32, outer - sign * 0.06))
        panel("Radiator_%s" % tag, "Trim", lo, hi, Y + 0.22, Y + 0.82,
              wz - 0.75, wz + 0.75, "Mat_metal")


def dress_window_x(tag, Y, outer_z, sign, wx):
    """Same, for the corridor-end windows in a wall that runs along X."""
    lo, hi = sorted((outer_z - sign * 0.05, outer_z))
    panel("WinJambA_%s" % tag, "Trim", wx - WIN_W / 2 - 0.09, wx - WIN_W / 2 + 0.03,
          Y + WIN_SILL, Y + WIN_HEAD, lo, hi, "Mat_wood", shadows=False)
    panel("WinJambB_%s" % tag, "Trim", wx + WIN_W / 2 - 0.03, wx + WIN_W / 2 + 0.09,
          Y + WIN_SILL, Y + WIN_HEAD, lo, hi, "Mat_wood", shadows=False)
    panel("WinHead_%s" % tag, "Trim", wx - WIN_W / 2 - 0.09, wx + WIN_W / 2 + 0.09,
          Y + WIN_HEAD - 0.06, Y + WIN_HEAD + 0.06, lo, hi, "Mat_wood", shadows=False)
    lo, hi = sorted((outer_z - sign * 0.26, outer_z))
    panel("WinSill_%s" % tag, "Trim", wx - WIN_W / 2 - 0.12, wx + WIN_W / 2 + 0.12,
          Y + WIN_SILL - 0.07, Y + WIN_SILL, lo, hi, "Mat_wood")
    lo, hi = sorted((outer_z - sign * 0.09, outer_z - sign * 0.04))
    panel("WinMullV_%s" % tag, "Trim", wx - 0.05, wx + 0.05,
          Y + WIN_SILL, Y + WIN_HEAD, lo, hi, "Mat_wood", shadows=False)
    panel("WinMullH_%s" % tag, "Trim", wx - WIN_W / 2, wx + WIN_W / 2,
          Y + 1.83, Y + 1.91, lo, hi, "Mat_wood", shadows=False)
    lo, hi = sorted((outer_z - sign * 0.185, outer_z - sign * 0.165))
    panel("WinGlass_%s" % tag, "Trim", wx - WIN_W / 2 + 0.01, wx + WIN_W / 2 - 0.01,
          Y + WIN_SILL + 0.01, Y + WIN_HEAD - 0.01, lo, hi, "Mat_glass", shadows=False)


DOOR_GAP = 0.035       # real gap between leaf and opening
LEAK_DEPTH = 0.13      # how far the glowing strip sits back inside that gap


def sealed_door(tag, x0, x1, top, z_face, z_back, inward, plank_rots):
    """A shut door filling an opening. `inward` is +1 when the room side is at
    greater z than the leaf, -1 when it is at less."""
    g = DOOR_GAP
    # Leaf, inset all round so the gap around it is genuine geometry.
    lo_z, hi_z = sorted((z_face, z_back))
    box(tag + "Leaf", "Entrance", x0 + g, x1 - g, 0.0, top - g, lo_z, hi_z, "Mat_wood")

    # Night seeping through the gap, set back in the reveal so it reads as a
    # line of light behind the door rather than paint on its face.
    lz = z_face - inward * LEAK_DEPTH
    lo_z, hi_z = sorted((lz, lz + inward * 0.04))
    for k, (a, b, c, d) in enumerate(((x0, x0 + g, 0.0, top),
                                      (x1 - g, x1, 0.0, top),
                                      (x0, x1, top - g, top))):
        panel("%sLeak%d" % (tag, k), "Entrance", a, b, c, d, lo_z, hi_z,
              "Mat_leak", shadows=False)

    # Architrave: three members round the opening, not a slab over it.
    az = z_face + inward * 0.05
    lo_z, hi_z = sorted((az, z_face))
    for k, (a, b, c, d) in enumerate(((x0 - 0.17, x0, 0.0, top + 0.17),
                                      (x1, x1 + 0.17, 0.0, top + 0.17),
                                      (x0 - 0.17, x1 + 0.17, top, top + 0.17))):
        panel("%sArch%d" % (tag, k), "Entrance", a, b, c, d, lo_z, hi_z, "Mat_wood")

    # Boards nailed across it, at an angle.
    pz = z_face + inward * 0.06
    span = (x1 - x0) * 1.06
    for k, (yy, rot) in enumerate(plank_rots):
        deco("%sPlank%d" % (tag, k), "Entrance", (x0 + x1) / 2, yy, pz,
             span, 0.22, 0.07, "Mat_wood", rot_y=0.0)
        # rot_y turns about the wrong axis for a board lying flat on a wall,
        # so tilt it in the XY plane by hand.
        c, sn = math.cos(rot), math.sin(rot)
        nodes[-1] = nodes[-1].replace(
            "transform = Transform3D(%.6g, 0, -0, 0, 0.22, 0, 0, 0, 0.07," % span,
            "transform = Transform3D(%.6g, %.6g, 0, %.6g, %.6g, 0, 0, 0, 0.07,"
            % (span * c, span * sn, -0.22 * sn, 0.22 * c))


def windowed_wall_z(tag, parent, x0, x1, Y, z0, z1, wins):
    """Outer wall running along Z, opened up at each window centre in `wins`."""
    box(tag + "_Sill", parent, x0, x1, Y, Y + WIN_SILL, z0, z1, "Mat_plaster")
    box(tag + "_Head", parent, x0, x1, Y + WIN_HEAD, Y + CEIL_H, z0, z1, "Mat_plaster")
    edges = [z0]
    for w in sorted(wins):
        edges += [w - WIN_W / 2, w + WIN_W / 2]
    edges.append(z1)
    for i in range(0, len(edges) - 1, 2):
        a, b = edges[i], edges[i + 1]
        if b - a > 0.01:
            box("%s_Pier%d" % (tag, i // 2), parent, x0, x1,
                Y + WIN_SILL, Y + WIN_HEAD, a, b, "Mat_plaster")


def windowed_wall_x(tag, parent, z0, z1, Y, x0, x1, wins):
    """Outer wall running along X, opened up at each window centre in `wins`."""
    box(tag + "_Sill", parent, x0, x1, Y, Y + WIN_SILL, z0, z1, "Mat_plaster")
    box(tag + "_Head", parent, x0, x1, Y + WIN_HEAD, Y + CEIL_H, z0, z1, "Mat_plaster")
    edges = [x0]
    for w in sorted(wins):
        edges += [w - WIN_W / 2, w + WIN_W / 2]
    edges.append(x1)
    for i in range(0, len(edges) - 1, 2):
        a, b = edges[i], edges[i + 1]
        if b - a > 0.01:
            box("%s_Pier%d" % (tag, i // 2), parent, a, b,
                Y + WIN_SILL, Y + WIN_HEAD, z0, z1, "Mat_plaster")


# -- Shell: slabs, ceilings, roof, outer walls -------------------------------
def slab_pieces(has_opening):
    if not has_opening:
        return [(-EDGE_X, EDGE_X, EDGE_Z0, EDGE_Z1)]
    return [(-EDGE_X, OP_X0, EDGE_Z0, EDGE_Z1),
            (OP_X0, EDGE_X, OP_Z1, EDGE_Z1),
            (OP_X0, EDGE_X, EDGE_Z0, OP_Z0),
            (OP_X1, EDGE_X, OP_Z0, OP_Z1)]


for fi in range(FLOORS):
    Y = FLOOR_Y[fi]
    for pi, (x0, x1, z0, z1) in enumerate(slab_pieces(fi > 0)):
        box("Slab%d_%d" % (fi, pi), "Shell", x0, x1, Y - SLAB, Y, z0, z1, "Mat_floor")
    # The slab carries the floor texture; the ceiling below it gets its own thin
    # facing so the two surfaces do not have to share one material.
    for pi, (x0, x1, z0, z1) in enumerate(slab_pieces(fi + 1 < FLOORS)):
        panel("Ceil%d_%d" % (fi, pi), "Trim", x0, x1, Y + CEIL_H - 0.04, Y + CEIL_H,
              z0, z1, "Mat_ceiling", shadows=False)

box("Roof", "Shell", -EDGE_X, EDGE_X, ROOF_Y, ROOF_Y + SLAB, EDGE_Z0, EDGE_Z1, "Mat_floor")

for fi in range(FLOORS):
    Y = FLOOR_Y[fi]
    # Ward block: one window per room, on the room centreline. Regular spacing
    # is the point -- an institution repeats itself.
    windowed_wall_z("OuterW%d" % fi, "Shell", -EDGE_X, -OUT_X + T / 2, Y,
                    EDGE_Z0, EDGE_Z1, list(DOORS) + [HALL_WIN_Z])
    windowed_wall_z("OuterE%d" % fi, "Shell", OUT_X - T / 2, EDGE_X, Y,
                    EDGE_Z0, EDGE_Z1, list(DOORS) + [HALL_WIN_Z])
    if fi == 0:
        # The front doors, dead ahead when the player turns round off the tarp.
        dl, dr = DOOR_HALL_X - DOOR_HALL_W / 2, DOOR_HALL_X + DOOR_HALL_W / 2
        box("OuterS0_W", "Shell", -EDGE_X, dl, Y, Y + CEIL_H, EDGE_Z0, HALL_Z0, "Mat_plaster")
        box("OuterS0_E", "Shell", dr, EDGE_X, Y, Y + CEIL_H, EDGE_Z0, HALL_Z0, "Mat_plaster")
        box("OuterS0_Head", "Shell", dl, dr, Y + 2.9, Y + CEIL_H, EDGE_Z0, HALL_Z0, "Mat_plaster")
    else:
        box("OuterS%d" % fi, "Shell", -EDGE_X, EDGE_X, Y, Y + CEIL_H, EDGE_Z0, HALL_Z0, "Mat_plaster")
    if fi == 0:
        # Ground floor north end: the entrance. Wall either side of a doorway
        # that is filled solid with a chained door leaf.
        box("OuterN0_W", "Shell", -EDGE_X, -1.6, Y, Y + CEIL_H, COR_Z1, EDGE_Z1, "Mat_plaster")
        box("OuterN0_E", "Shell", 1.6, EDGE_X, Y, Y + CEIL_H, COR_Z1, EDGE_Z1, "Mat_plaster")
        box("OuterN0_Head", "Shell", -1.6, 1.6, Y + 2.8, Y + CEIL_H, COR_Z1, EDGE_Z1, "Mat_plaster")
    else:
        # Upper floors get a tall window where the ground floor has its door, so
        # every corridor ends in light you cannot reach.
        windowed_wall_x("OuterN%d" % fi, "Shell", COR_Z1, EDGE_Z1, Y,
                        -EDGE_X, EDGE_X, [0.0])

    # Wall between the stair hall and the ward block, open at the corridor mouth.
    box("HallWallW%d" % fi, "Shell", -EDGE_X, -WALL_X, Y, Y + CEIL_H, COR_Z0 - T / 2, COR_Z0 + T / 2, "Mat_plaster")
    box("HallWallE%d" % fi, "Shell", WALL_X, EDGE_X, Y, Y + CEIL_H, COR_Z0 - T / 2, COR_Z0 + T / 2, "Mat_plaster")
    box("HallLintel%d" % fi, "Shell", -WALL_X, WALL_X, Y + DOOR_H + 0.3, Y + CEIL_H,
        COR_Z0 - T / 2, COR_Z0 + T / 2, "Mat_plaster")


# -- Corridors ---------------------------------------------------------------
def wall_runs():
    edges = [COR_Z0 + T / 2]
    for d in DOORS:
        edges += [d - DOOR_W / 2, d + DOOR_W / 2]
    edges.append(COR_Z1)
    return [(edges[i], edges[i + 1]) for i in range(0, len(edges) - 1, 2)]


RUNS = wall_runs()

for fi in range(FLOORS):
    Y = FLOOR_Y[fi]
    for sign, side in ((-1, "W"), (1, "E")):
        xc = sign * WALL_X
        face = sign * COR_HW
        for ri, (z0, z1) in enumerate(RUNS):
            box("Cor%s%d_%d" % (side, fi, ri), "Corridor",
                xc - T / 2, xc + T / 2, Y, Y + CEIL_H, z0, z1, "Mat_plaster")
            # The painted band and the trolley rail: the two things every one of
            # these corridors has, and the reason they read as a hospital.
            lo, hi = sorted((face - sign * 0.03, face))
            panel("Dado%s%d_%d" % (side, fi, ri), "Trim",
                  lo, hi, Y, Y + DADO_H, z0, z1, "Mat_dado", shadows=False)
            lo, hi = sorted((face - sign * 0.11, face - sign * 0.02))
            panel("Rail%s%d_%d" % (side, fi, ri), "Trim",
                  lo, hi, Y + RAIL_Y, Y + RAIL_Y + 0.09,
                  z0 + 0.15, z1 - 0.15, "Mat_wood", shadows=False)
        for di, d in enumerate(DOORS):
            box("Lint%s%d_%d" % (side, fi, di), "Corridor",
                xc - T / 2, xc + T / 2, Y + DOOR_H, Y + CEIL_H,
                d - DOOR_W / 2, d + DOOR_W / 2, "Mat_plaster")
            for k, zz in enumerate((d - DOOR_W / 2, d + DOOR_W / 2)):
                panel("Jamb%s%d_%d_%d" % (side, fi, di, k), "Trim",
                      xc - T / 2 - 0.07, xc + T / 2 + 0.07, Y, Y + DOOR_H + 0.09,
                      zz - 0.08, zz + 0.08, "Mat_wood")
            panel("Head%s%d_%d" % (side, fi, di), "Trim",
                  xc - T / 2 - 0.07, xc + T / 2 + 0.07, Y + DOOR_H, Y + DOOR_H + 0.09,
                  d - DOOR_W / 2 - 0.08, d + DOOR_W / 2 + 0.08, "Mat_wood")

    # Room dividers.
    for di, z in enumerate(DIVS):
        box("DivW%d_%d" % (fi, di), "Rooms", -OUT_X + T / 2, -WALL_X, Y, Y + CEIL_H,
            z - T / 2, z + T / 2, "Mat_plaster")
        box("DivE%d_%d" % (fi, di), "Rooms", WALL_X, OUT_X - T / 2, Y, Y + CEIL_H,
            z - T / 2, z + T / 2, "Mat_plaster")

    # Corridor clutter and the plaster that has come off the walls.
    for i in range(7):
        z = 3.0 + i * 7.6
        cx = rng.uniform(-2.4, 2.4)
        panel("CorDebris%d_%d" % (fi, i), "Props", cx - 0.9, cx + 0.9, Y, Y + 0.16,
              z - rng.uniform(0.5, 1.1), z + rng.uniform(0.5, 1.1), "Mat_rubble", shadows=False)
    for i in range(4):
        z = 9.0 + i * 12.0
        x = rng.choice([-2.2, 2.2])
        yaw = rng.uniform(-0.35, 0.35)
        csg("CorGurney%d_%d" % (fi, i), "Props", x, Y + 0.62, z, 0.78, 0.14, 1.9,
            "Mat_metal", rot_y=yaw)
        deco("CorGurneyLeg%d_%d" % (fi, i), "Props", x, Y + 0.31, z, 0.66, 0.62, 1.7,
             "Mat_metal", rot_y=yaw, shadows=False)
    # Peeled patches, so the brick behind shows at eye level down the run.
    for i in range(6):
        sg = rng.choice([-1, 1])
        z = rng.uniform(COR_Z0 + 3, COR_Z1 - 3)
        h = rng.uniform(0.5, 1.3)
        y0 = Y + rng.uniform(DADO_H, CEIL_H - h - 0.3)
        lo, hi = sorted((sg * COR_HW - sg * 0.035, sg * COR_HW - sg * 0.005))
        panel("CorPeel%d_%d" % (fi, i), "Trim", lo, hi, y0, y0 + h,
              z, z + rng.uniform(0.7, 1.9), "Mat_brick", shadows=False)


# -- Ward rooms --------------------------------------------------------------
ROOMS = []
for fi in range(FLOORS):
    for bi, (z0, z1) in enumerate(BANDS):
        for sign, side in ((-1, "W"), (1, "E")):
            ROOMS.append((fi, side, bi, sign, sign * (COR_HW + ROOM_X) / 2, (z0 + z1) / 2))

for fi, side, bi, sign, rx, rz in ROOMS:
    Y = FLOOR_Y[fi]
    tag = "%s%d_%d" % (side, fi, bi)
    outer = sign * ROOM_X
    zin0, zin1 = rz - 6.6, rz + 6.6

    # Painted band along the outer wall, matching the corridor exactly.
    lo, hi = sorted((outer - sign * 0.03, outer))
    panel("RmDado_%s" % tag, "Trim", lo, hi, Y, Y + DADO_H, zin0, zin1, "Mat_dado", shadows=False)

    dress_window_z("Rm%s" % tag, Y, outer, sign, rz)

    # Two beds against the outer wall, one usually shoved out of line. Built as
    # mattress / frame rail / under-mass / head and foot boards -- a single slab
    # on a block reads as a plinth, not a bed.
    for b in range(2):
        bx = rx + sign * 4.6
        bz = rz + (-4.2 if b == 0 else 4.2) + rng.uniform(-0.7, 0.7)
        yaw = rng.uniform(-0.22, 0.22) + (rng.uniform(0.5, 1.1) if rng.random() < 0.22 else 0.0)
        csg("Bed_%s_%d" % (tag, b), "Props", bx, Y + 0.66, bz, 0.86, 0.2, 1.82,
            "Mat_mattress", rot_y=yaw)
        deco("BedRail_%s_%d" % (tag, b), "Props", bx, Y + 0.52, bz, 0.98, 0.1, 2.0,
             "Mat_metal", rot_y=yaw, shadows=False)
        deco("BedUnder_%s_%d" % (tag, b), "Props", bx, Y + 0.24, bz, 0.72, 0.44, 1.74,
             "Mat_metal", rot_y=yaw, shadows=False)
        deco("BedHead_%s_%d" % (tag, b), "Props", bx, Y + 0.94, bz - 1.0, 1.0, 0.78, 0.07,
             "Mat_metal", rot_y=yaw)
        deco("BedFoot_%s_%d" % (tag, b), "Props", bx, Y + 0.78, bz + 1.0, 1.0, 0.46, 0.07,
             "Mat_metal", rot_y=yaw)

    csg("Cabinet_%s" % tag, "Props", rx - sign * 2.4, Y + 0.42,
        rz + rng.uniform(-5.2, 5.2), 0.56, 0.84, 0.5, "Mat_wood",
        rot_y=rng.uniform(-0.6, 0.6))
    csg("Locker_%s" % tag, "Props", rx + rng.uniform(-1.0, 1.0), Y + 0.9,
        rz + rng.choice([-5.6, 5.6]), 0.9, 1.8, 0.55, "Mat_metal",
        rot_y=rng.uniform(-0.4, 0.4))

    # Collapse: plaster off the wall, boards off the ceiling.
    panel("Rubble_%s" % tag, "Props", rx - 1.6, rx + 1.6, Y, Y + 0.22,
          rz - 1.4, rz + 1.4, "Mat_rubble", shadows=False)
    for p in range(2):
        deco("Plank_%s_%d" % (tag, p), "Props",
             rx + rng.uniform(-3.5, 3.5), Y + 0.07, rz + rng.uniform(-5.5, 5.5),
             rng.uniform(1.4, 2.6), 0.08, 0.22, "Mat_wood",
             rot_y=rng.uniform(0, math.pi), shadows=False)
    # A patch of the divider wall gone, brick behind it.
    ph = rng.uniform(0.8, 1.8)
    py = Y + rng.uniform(0.2, CEIL_H - ph - 0.4)
    panel("RmPeel_%s" % tag, "Trim", rx - 2.2, rx + 0.6, py, py + ph,
          zin1 - 0.04, zin1 - 0.01, "Mat_brick", shadows=False)

    nodes.append(
        '[node name="Room_%s" type="Marker3D" parent="Rooms"]\n'
        'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4g, %.4g, %.4g)\n'
        'metadata/room_extents = Vector2(4.4, 5.4)' % (tag, rx, Y, rz))


# -- Stairs ------------------------------------------------------------------
for fi in range(FLOORS - 1):
    Y = FLOOR_Y[fi]
    Yt = FLOOR_Y[fi + 1]
    xc = (ST_X0 + ST_X1) / 2
    w = ST_X1 - ST_X0
    # The walkable surface is a smooth ramp: the player has no step-up, so real
    # treads would be an unclimbable wall. Treads are laid over it as scenery.
    ramp("StairRamp%d" % fi, "Stairs", xc, w, ST_ZB, Y, ST_ZT, Yt, 0.55, "Mat_floor")
    run = (ST_ZT - ST_ZB) / ST_STEPS
    rise = (Yt - Y) / ST_STEPS
    # Held clear of the parapets on both sides -- run to the full flight width
    # and the tread corners poke out through the outside face of the wall.
    tx0, tx1 = ST_X0 + 0.26, ST_X1 - 0.26
    for s in range(ST_STEPS):
        z0 = ST_ZB + s * run
        top = Y + (s + 1) * rise
        panel("Tread%d_%d" % (fi, s), "Stairs", tx0, tx1, top - 0.13, top,
              z0, z0 + run, "Mat_floor", shadows=False)
        panel("Riser%d_%d" % (fi, s), "Stairs", tx0, tx1, top - rise, top - 0.12,
              z0 + run - 0.09, z0 + run, "Mat_plaster", shadows=False)
    # A parapet up each side, with a timber rail along the top. `thick` runs
    # DOWN from the surface the ramp helper is given, so the parapet has to be
    # specified at its coping height -- given at ramp level it becomes a buried
    # slab and the player simply walks off the edge of the flight.
    for sx, tag in ((ST_X0 + 0.11, "W"), (ST_X1 - 0.11, "E")):
        ramp("StairParapet%s%d" % (tag, fi), "Stairs", sx, 0.22,
             ST_ZB, Y + 0.95, ST_ZT, Yt + 0.95, 1.05, "Mat_plaster")
        ramp("StairRail%s%d" % (tag, fi), "Stairs", sx, 0.28,
             ST_ZB, Y + 1.04, ST_ZT, Yt + 1.04, 0.09, "Mat_wood", collide=False)

# Balustrade around the void on every floor the stair passes through.
for fi in range(1, FLOORS):
    Y = FLOOR_Y[fi]
    box("VoidW%d" % fi, "Stairs", OP_X0 - 0.12, OP_X0, Y, Y + 1.0, OP_Z0, OP_Z1, "Mat_plaster")
    box("VoidE%d" % fi, "Stairs", OP_X1, OP_X1 + 0.12, Y, Y + 1.0, OP_Z0, OP_Z1, "Mat_plaster")
    box("VoidS%d" % fi, "Stairs", OP_X0, OP_X1, Y, Y + 1.0, OP_Z0, OP_Z0 + 0.12, "Mat_plaster")


# -- Stair hall (all floors) and the base camp on the ground floor -----------
for fi in range(FLOORS):
    Y = FLOOR_Y[fi]
    for i in range(2):
        pz = -14.5 if i == 0 else -4.5
        csg("HallPillar%d_%d" % (fi, i), "Hall", -11.0, Y + CEIL_H / 2, pz,
            1.05, CEIL_H, 1.05, "Mat_plaster")
    # Split around the front doorway -- run as one band it paints a green stripe
    # straight across the door.
    _gl, _gr = DOOR_HALL_X - DOOR_HALL_W / 2 - 0.17, DOOR_HALL_X + DOOR_HALL_W / 2 + 0.17
    for _k, (_a, _b) in enumerate(((-EDGE_X + T, _gl), (_gr, EDGE_X - T))):
        if _b - _a > 0.05:
            panel("HallDadoS%d_%d" % (fi, _k), "Trim", _a, _b, Y, Y + DADO_H,
                  HALL_Z0, HALL_Z0 + 0.03, "Mat_dado", shadows=False)
    panel("HallDadoW%d" % fi, "Trim", -ROOM_X, -ROOM_X + 0.03, Y, Y + DADO_H,
          HALL_Z0, COR_Z0, "Mat_dado", shadows=False)
    panel("HallRubble%d" % fi, "Props", -15.0, -12.2, Y, Y + 0.2, -8.0, -5.4,
          "Mat_rubble", shadows=False)

# -- Entrance lobby ---------------------------------------------------------
# This is the way in, so it has to read as a lobby the moment the player turns
# round off the tarp: front doors, a counter, a board, benches.
for _fi in range(FLOORS):
    _Y = FLOOR_Y[_fi]
    for _sign, _side in ((-1, "W"), (1, "E")):
        dress_window_z("Hall%s%d" % (_side, _fi), _Y, _sign * ROOM_X, _sign,
                       HALL_WIN_Z, radiator=False)
    if _fi > 0:
        dress_window_x("CorEnd%d" % _fi, _Y, COR_Z1, -1, 0.0)

csg("ReceptionDesk", "Hall", -8.6, 0.55, -8.0, 3.8, 1.1, 0.9, "Mat_wood")
deco("DeskTop", "Hall", -8.6, 1.14, -8.0, 4.1, 0.1, 1.1, "Mat_wood")
csg("ReceptionReturn", "Hall", -10.35, 0.55, -6.1, 0.9, 1.1, 3.0, "Mat_wood")
deco("ReturnTop", "Hall", -10.35, 1.14, -6.1, 1.1, 0.1, 3.2, "Mat_wood")
csg("ReceptionBack", "Hall", -13.4, 1.05, -7.0, 0.5, 2.1, 4.2, "Mat_wood")
deco("PigeonHoles", "Hall", -13.1, 1.35, -7.0, 0.08, 1.2, 3.8, "Mat_metal", shadows=False)
deco("NoticeBoard", "Hall", -15.9, 1.75, -11.5, 0.08, 1.1, 2.6, "Mat_wood")
deco("NoticePaper", "Hall", -15.83, 1.75, -11.5, 0.03, 0.8, 2.2, "Mat_mattress", shadows=False)
for i, bz in enumerate((-15.0, -12.6)):
    csg("Bench%d" % i, "Hall", -13.2, 0.44, bz, 1.5, 0.12, 0.55, "Mat_wood")
    deco("BenchLegs%d" % i, "Hall", -13.2, 0.19, bz, 1.3, 0.38, 0.42, "Mat_metal", shadows=False)
    deco("BenchBack%d" % i, "Hall", -13.55, 0.78, bz, 0.1, 0.56, 0.55, "Mat_wood", shadows=False)
deco("LobbyRadiator", "Hall", 15.7, 0.52, -6.0, 0.24, 0.6, 2.2, "Mat_metal")

# The front doors. Boarded from the outside like the far end of the corridor --
# both ways out of this building are shut.
_dl, _dr = DOOR_HALL_X - DOOR_HALL_W / 2, DOOR_HALL_X + DOOR_HALL_W / 2
sealed_door("Front", _dl, _dr, 2.9, HALL_Z0, EDGE_Z0, 1,
            ((0.95, -0.11), (1.85, 0.14), (2.45, -0.07)))
deco("FrontDoorMullion", "Entrance", DOOR_HALL_X, 1.42, HALL_Z0 - 0.02,
     0.09, 2.76, 0.1, "Mat_wood")
spot("FrontGlowLight", "Lights", DOOR_HALL_X, 2.0, HALL_Z0 + 0.6, math.pi,
     (0.46, 0.56, 0.76), 1.5, 14.0, 60.0)
nodes.append(
    '[node name="FrontDoorZone" type="Area3D" parent="Entrance"]\n'
    "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4g, 1.2, %.4g)\n"
    'script = ExtResource("s_sealed")\n'
    'message = "The front doors will not move.\\nSomething heavy is against them."'
    % (DOOR_HALL_X, HALL_Z0 + 2.0))
nodes.append(
    '[node name="CollisionShape3D" type="CollisionShape3D" parent="Entrance/FrontDoorZone"]\n'
    'shape = SubResource("BoxShape_doorzone")')


# -- The doors that do not open ----------------------------------------------
sealed_door("Sealed", -1.6, 1.6, 2.8, COR_Z1, EDGE_Z1, -1,
            ((0.85, 0.16), (1.75, -0.13), (2.35, 0.09)))
spot("EntranceGlow", "Lights", 0.0, 2.0, COR_Z1 - 0.6, 0.0,
     (0.46, 0.56, 0.76), 2.2, 26.0, 62.0)
nodes.append(
    '[node name="SealedDoorZone" type="Area3D" parent="Entrance"]\n'
    "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.2, %.4g)\n"
    'script = ExtResource("s_sealed")' % (COR_Z1 - 2.2))
nodes.append(
    '[node name="CollisionShape3D" type="CollisionShape3D" parent="Entrance/SealedDoorZone"]\n'
    'shape = SubResource("BoxShape_doorzone")')


# -- Lighting ----------------------------------------------------------------
PENDANT_Z = [10.5, 24.5, 38.5, 52.5]
for fi in range(FLOORS):
    Y = FLOOR_Y[fi]
    lit = rng.sample(range(len(PENDANT_Z)), 2)
    flick = lit[0]
    for i, z in enumerate(PENDANT_Z):
        cord_len = 0.55
        deco("Cord%d_%d" % (fi, i), "Lights", 0.0, Y + CEIL_H - cord_len / 2, z,
             0.03, cord_len, 0.03, "Mat_wood", shadows=False)
        bulb_mat = "Mat_bulb" if i in lit else "Mat_metal"
        deco("Bulb%d_%d" % (fi, i), "Lights", 0.0, Y + CEIL_H - cord_len - 0.09, z,
             0.17, 0.2, 0.17, bulb_mat, shadows=False)
        if i in lit:
            omni("Pendant%d_%d" % (fi, i), "Lights", 0.0, Y + CEIL_H - cord_len - 0.14, z,
                 (0.6, 0.72, 0.54), 0.85, 12.0, flicker=(i == flick))
    # A dying fixture over the stair on every landing.
    omni("StairLight%d" % fi, "Lights", (ST_X0 + ST_X1) / 2, Y + CEIL_H - 0.35, -4.4,
         (0.5, 0.62, 0.5), 1.0, 13.0, flicker=(fi != 0), shadows=False)

omni("CampLight", "Lights", TARP[0] + 0.4, 1.4, TARP[2], (1.0, 0.72, 0.42), 0.9, 9.0, shadows=False)


# -- Outside ----------------------------------------------------------------
# There is now a real hole in the wall at every window, so there has to be
# something on the other side of it. Kept cheap and low: ground, a scatter of
# dead trees close enough to read, and a moon to silhouette them against.
box("Ground", "Exterior", -360, 360, -1.2, -0.5, -360, 400, "Mat_ground")
for i, (gx, gz, gw, gd, gh) in enumerate((
        (-135, 20, 150, 300, 34.0), (-105, 150, 140, 130, 26.0),
        (135, 20, 150, 300, 30.0), (110, -90, 140, 120, 24.0),
        (0, 205, 340, 130, 38.0), (-60, 175, 150, 90, 28.0),
        (0, -165, 340, 120, 30.0), (70, -140, 150, 90, 25.0))):
    box("Ridge%d" % i, "Exterior", gx - gw / 2, gx + gw / 2, -1.0, gh - 1.0,
        gz - gd / 2, gz + gd / 2, "Mat_ground", collide=False)

# Weighted toward the dead one -- it is the most useful silhouette for this.
TREES = ["t_tree_dead", "t_tree_fir", "t_tree_oak", "t_tree_dead",
         "t_tree_aleppo", "t_tree_plane"]
_placed = 0
for band_x in (-1, 1):
    for i in range(38):
        tx = band_x * rng.uniform(25.0, 62.0)
        tz = rng.uniform(-42.0, 82.0)
        sc = rng.uniform(1.7, 2.7)
        yaw = rng.uniform(0, math.tau)
        c, s2 = math.cos(yaw), math.sin(yaw)
        nodes.append(
            '[node name="Tree%d" parent="Exterior" instance=ExtResource("%s")]\n'
            "transform = Transform3D(%.5g, 0, %.5g, 0, %.5g, 0, %.5g, 0, %.5g, %.3g, -0.5, %.3g)"
            % (_placed, TREES[_placed % len(TREES)],
               c * sc, s2 * sc, sc, -s2 * sc, c * sc, tx, tz))
        _placed += 1
for i in range(26):
    tx = rng.uniform(-62.0, 62.0)
    tz = rng.choice([rng.uniform(-72.0, -30.0), rng.uniform(68.0, 108.0)])
    sc = rng.uniform(1.8, 2.9)
    nodes.append(
        '[node name="Tree%d" parent="Exterior" instance=ExtResource("%s")]\n'
        "transform = Transform3D(%.5g, 0, 0, 0, %.5g, 0, 0, 0, %.5g, %.3g, -0.5, %.3g)"
        % (_placed, TREES[_placed % len(TREES)], sc, sc, sc, tx, tz))
    _placed += 1

nodes.append(
    '[node name="Moonlight" type="DirectionalLight3D" parent="Exterior"]\n'
    "transform = Transform3D(0.7895, 0.5035, -0.35, 0, 0.5702, 0.82, "
    "0.614, -0.6474, 0.45, 0, 40, 0)\n"
    "light_color = Color(0.58, 0.7, 1, 1)\n"
    "light_energy = 1.35\n"
    "shadow_enabled = true\n"
    "shadow_bias = 0.06\n"
    "directional_shadow_max_distance = 90.0")


# -- Header / footer ---------------------------------------------------------
def mat(mid, tex, tint, rough, scale, extra=""):
    return '''[sub_resource type="StandardMaterial3D" id="%s"]
albedo_color = Color(%g, %g, %g, 1)
albedo_texture = ExtResource("%s")
texture_filter = 0
roughness = %g
uv1_scale = Vector3(%g, %g, %g)
uv1_triplanar = true
uv1_world_triplanar = true
uv1_triplanar_sharpness = 4.0%s

''' % (mid, tint[0], tint[1], tint[2], tex, rough, scale, scale, scale, extra)


HEADER = '''[gd_scene format=3 uid="uid://buytrovpa81uh"]

[ext_resource type="Script" uid="uid://dhb6lsyfv14uv" path="res://scripts/level.gd" id="1_level"]
[ext_resource type="PackedScene" uid="uid://dyggwvlcccl7g" path="res://models/props/Tarp.tscn" id="2_tarp"]
[ext_resource type="PackedScene" uid="uid://cy247l8eaf4p" path="res://models/props/OilLamp.tscn" id="3_lamp"]
[ext_resource type="AudioStream" uid="uid://cmclcgt3kghuc" path="res://audio/forest_ambience.wav" id="4_ambience"]
[ext_resource type="Script" uid="uid://dx1llhu3gv50h" path="res://scripts/lamp_flicker.gd" id="s_flicker"]
[ext_resource type="Script" uid="uid://c0w135ge5f5hd" path="res://scripts/sealed_door.gd" id="s_sealed"]
[ext_resource type="Texture2D" uid="uid://4lf4rkwdwpb4" path="res://textures/retro/plaster.tga" id="t_plaster"]
[ext_resource type="Texture2D" uid="uid://cmlsdoj4kkxcj" path="res://textures/retro/dado.tga" id="t_dado"]
[ext_resource type="Texture2D" uid="uid://dondpkievg83" path="res://textures/retro/brick.tga" id="t_brick"]
[ext_resource type="Texture2D" uid="uid://bygpfx5qnkcgv" path="res://textures/retro/floor.tga" id="t_floor"]
[ext_resource type="Texture2D" uid="uid://c3k10a2xmldf6" path="res://textures/retro/ceiling.tga" id="t_ceiling"]
[ext_resource type="Texture2D" uid="uid://b3rqb80icygvp" path="res://textures/retro/wood.tga" id="t_wood"]
[ext_resource type="Texture2D" uid="uid://c4uhydk368uhm" path="res://textures/retro/metal.tga" id="t_metal"]
[ext_resource type="Texture2D" uid="uid://x7rpemm4avdl" path="res://textures/retro/rubble.tga" id="t_rubble"]
[ext_resource type="Texture2D" uid="uid://b4sqaxmfjlcp5" path="res://textures/retro_moon.png" id="t_moon"]
[ext_resource type="PackedScene" uid="uid://cfyujvk56df3b" path="res://models/environment/trees/Tree_Dead.tscn" id="t_tree_dead"]
[ext_resource type="PackedScene" path="res://models/environment/trees/Tree_Fir.tscn" id="t_tree_fir"]
[ext_resource type="PackedScene" uid="uid://djgblr74x8xn6" path="res://models/environment/trees/Tree_KermesOak.tscn" id="t_tree_oak"]
[ext_resource type="PackedScene" path="res://models/environment/trees/Tree_AleppoPine.tscn" id="t_tree_aleppo"]
[ext_resource type="PackedScene" uid="uid://bwlbxs2arv2yx" path="res://models/environment/trees/Tree_Plane.tscn" id="t_tree_plane"]

[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_l3"]
sky_top_color = Color(0.03, 0.045, 0.09, 1)
sky_horizon_color = Color(0.14, 0.17, 0.24, 1)
sky_curve = 0.12
ground_bottom_color = Color(0.02, 0.025, 0.03, 1)
ground_horizon_color = Color(0.11, 0.13, 0.17, 1)

[sub_resource type="Sky" id="Sky_l3"]
sky_material = SubResource("ProceduralSkyMaterial_l3")

[sub_resource type="StandardMaterial3D" id="Mat_moon"]
transparency = 1
blend_mode = 1
shading_mode = 0
albedo_texture = ExtResource("t_moon")
texture_filter = 0
billboard_mode = 1

[sub_resource type="Environment" id="Environment_l3"]
background_mode = 2
sky = SubResource("Sky_l3")
ambient_light_source = 2
ambient_light_color = Color(0.1, 0.13, 0.19, 1)
ambient_light_energy = 0.4
fog_enabled = true
fog_light_color = Color(0.045, 0.056, 0.07, 1)
fog_light_energy = 0.5
fog_density = 0.028
fog_sky_affect = 0.0

[sub_resource type="BoxMesh" id="BoxMesh_unit"]
size = Vector3(1, 1, 1)

[sub_resource type="BoxShape3D" id="BoxShape_doorzone"]
size = Vector3(4.4, 2.4, 3.6)

''' + mat("Mat_plaster", "t_plaster", (0.64, 0.62, 0.58), 0.96, 0.36) \
    + mat("Mat_dado", "t_dado", (0.78, 0.84, 0.82), 0.9, 0.42) \
    + mat("Mat_brick", "t_brick", (0.4, 0.35, 0.33), 1.0, 2.2) \
    + mat("Mat_floor", "t_floor", (0.66, 0.67, 0.64), 0.85, 0.4) \
    + mat("Mat_ceiling", "t_ceiling", (0.5, 0.5, 0.48), 1.0, 0.32) \
    + mat("Mat_wood", "t_wood", (0.82, 0.78, 0.74), 0.95, 0.7) \
    + mat("Mat_metal", "t_metal", (0.4, 0.41, 0.39), 0.7, 0.9, "\nmetallic = 0.3") \
    + mat("Mat_rubble", "t_rubble", (0.72, 0.7, 0.66), 1.0, 0.75)     + mat("Mat_mattress", "t_plaster", (0.75, 0.73, 0.66), 1.0, 1.6) + '''[sub_resource type="StandardMaterial3D" id="Mat_glass"]
; Refraction is deliberately NOT used here. Godot samples the screen texture
; for it, so the pane picked up the flashlight cone on the surrounding wall and
; smeared it into a bright blob. A grimy translucent grey does the job with no
; artefacts: the treeline stays readable, just hazed and dirty.
transparency = 1
cull_mode = 2
albedo_color = Color(0.62, 0.66, 0.68, 0.2)
albedo_texture = ExtResource("t_plaster")
roughness = 0.85
metallic = 0.0
specular = 0.15
texture_filter = 0
uv1_scale = Vector3(1.4, 1.4, 1.4)
uv1_triplanar = true
uv1_world_triplanar = true

[sub_resource type="StandardMaterial3D" id="Mat_ground"]
albedo_color = Color(0.33, 0.34, 0.29, 1)
albedo_texture = ExtResource("t_rubble")
texture_filter = 0
roughness = 1.0
uv1_scale = Vector3(0.12, 0.12, 0.12)
uv1_triplanar = true
uv1_world_triplanar = true

[sub_resource type="StandardMaterial3D" id="Mat_leak"]
; Night leaking past a shut door, not daylight. The old value was a blown-out
; white that read as a glowing sticker on the woodwork, and made no sense
; against a moonlit exterior.
albedo_color = Color(0.26, 0.32, 0.42, 1)
roughness = 1.0
emission_enabled = true
emission = Color(0.42, 0.54, 0.74, 1)
emission_energy_multiplier = 0.42
texture_filter = 0

[sub_resource type="StandardMaterial3D" id="Mat_bulb"]
albedo_color = Color(1, 0.88, 0.62, 1)
emission_enabled = true
emission = Color(1, 0.82, 0.5, 1)
emission_energy_multiplier = 2.2
shading_mode = 0
texture_filter = 0

[node name="Level3" type="Node3D"]
script = ExtResource("1_level")
level_number = 3
indoor = true
carcass_quota = 6
room_occupancy = 0.62
baby_chance = 0.45
player_start_yaw_degrees = 180.0

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_l3")

[node name="LevelTimer" type="Timer" parent="."]
wait_time = 120.0
one_shot = true

[node name="Shell" type="Node3D" parent="."]

[node name="Corridor" type="Node3D" parent="."]

[node name="Rooms" type="Node3D" parent="."]

[node name="Stairs" type="Node3D" parent="."]

[node name="Hall" type="Node3D" parent="."]

[node name="Entrance" type="Node3D" parent="."]

[node name="Props" type="Node3D" parent="."]

[node name="Trim" type="Node3D" parent="."]

[node name="Exterior" type="Node3D" parent="."]

[node name="Lights" type="Node3D" parent="."]
'''

FOOTER = '''
[node name="Tarp" parent="." instance=ExtResource("2_tarp")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4g, %.4g, %.4g)

; The tarp is a 0.1m-thick slab. Outdoors it sits on bumpy terrain and its
; collision usefully flattens a patch; on this level's dead-flat concrete the
; same slab is a 5cm vertical step, and the player is a flat-bottomed cylinder
; with no step-up -- it walled the tarp off entirely. Dropped here to floor
; level and left as a mat: the floor already carries the player and the
; carcasses, and the drop zone keeps its own separate shape.
[node name="CollisionShape3D" parent="Tarp" index="1"]
disabled = true

[node name="OilLamp" parent="." instance=ExtResource("3_lamp")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4g, 0, %.4g)

[node name="AmbientSound" type="AudioStreamPlayer" parent="."]
stream = ExtResource("4_ambience")
volume_db = -20.0
autoplay = true
bus = &"retro_Retro"

[node name="UILayer" type="CanvasLayer" parent="."]

[node name="EndPanel" type="Panel" parent="UILayer"]
visible = false
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="EndText" type="Label" parent="UILayer/EndPanel"]
layout_mode = 0
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -52.0
offset_top = -11.5
offset_right = 52.0
offset_bottom = 11.5
text = "You survived."
''' % (TARP[0], TARP[1], TARP[2], TARP[0] + 4.3, TARP[2] + 0.4)

out = HEADER + "\n" + "\n\n".join(nodes) + "\n" + FOOTER
with open(r"x:/Vampire Game/vampire-game/scenes/levels/Level3.tscn", "w", newline="\n") as fh:
    fh.write(out)
csg_n = sum(1 for n in nodes if "CSGBox3D" in n)
mesh_n = sum(1 for n in nodes if "MeshInstance3D" in n)
print("Level3.tscn: %d nodes (%d CSG, %d mesh, %d other)"
      % (len(nodes), csg_n, mesh_n, len(nodes) - csg_n - mesh_n))
