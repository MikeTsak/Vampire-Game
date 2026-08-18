extends RefCounted
## Assembles the Skinwalker body from the rig, part by part.
##
## The creature stands upright, so the torso is a VERTICAL column and every
## wrap-around helper works on a horizontal cross-section: `ang == 0` is the
## spine ridge at the back (+Z) and `ang == PI` is the sternum (-Z).

const Atlas := preload("res://tools/sw_atlas.gd")

## Torso shell. Each entry is [centre, radius]; the centre sits forward of its
## spine bone by roughly half a radius, which keeps the backbone riding the
## rear of the ribcage without throwing the chest out past the head.
const TORSO := [
	[Vector3(0, 1.775, 0.035), 0.172],   # pelvis
	[Vector3(0, 1.950, 0.027), 0.133],   # waist, pinched in hard
	[Vector3(0, 2.100, -0.052), 0.208],
	[Vector3(0, 2.240, -0.129), 0.256],
	[Vector3(0, 2.365, -0.213), 0.300],  # ribcage, widest
	[Vector3(0, 2.470, -0.268), 0.266],
	[Vector3(0, 2.556, -0.269), 0.180],  # top of chest, under the shoulders
]

## The torso tube is swept with this cross-section squash, so anything that
## rides the shell -- ribs, ventral strip, wounds, mane -- has to use the same
## ellipse. Treating it as a circle floats the ribs off the flank.
const TORSO_SQUASH := Vector2(1.0, 0.86)

var m  # sw_mesh instance
var bones: Array

## 0 = full detail. Higher LODs drop ring counts and incidental detail, but
## never touch the antlers or the ribcage -- those two carry the silhouette
## and are the whole reason the creature reads at distance.
var lod := 0

func build(mesh, bone_list: Array, lod_level: int = 0) -> void:
	m = mesh
	bones = bone_list
	lod = lod_level
	_torso()
	_ventral()
	_rib_bed()
	_ribcage()
	_wounds()
	_neck()
	_skull()
	_antlers()
	_arms()
	_legs()
	if lod < 2:
		_blood()
		_fur()

## Ring count for the current LOD, floored at a triangular cross-section.
func _s(n: int) -> int:
	if lod == 0:
		return n
	return maxi(3, n - 2 if lod == 1 else n - 3)

func _bp(n: String) -> Vector3:
	for b in bones:
		if b["name"] == n:
			return b["pos"]
	push_error("sw_body: missing bone %s" % n)
	return Vector3.ZERO

# ------------------------------------------------------- torso cross-section

## Radial direction on the horizontal cross-section. 0 = spine ridge (+Z),
## PI = sternum (-Z), PI/2 = the creature's left flank (+X).
func _radial(ang: float) -> Vector3:
	return Vector3(sin(ang) * TORSO_SQUASH.x, 0.0, cos(ang) * TORSO_SQUASH.y)

func _torso_lerp(idx: float) -> Array:
	var i := clampi(int(floor(idx)), 0, TORSO.size() - 2)
	var f := clampf(idx - float(i), 0.0, 1.0)
	return [
		(TORSO[i][0] as Vector3).lerp(TORSO[i + 1][0], f),
		lerpf(float(TORSO[i][1]), float(TORSO[i + 1][1]), f),
	]

## Point on the shell, pushed out along the true radial normal.
func _torso_shell(idx: float, ang: float, push: float = 0.0) -> Vector3:
	var cs := _torso_lerp(idx)
	return (cs[0] as Vector3) + _radial(ang) * (float(cs[1]) + push)

## Same, but scaling the radius instead of adding to it.
func _torso_shell_mult(idx: float, ang: float, mult: float) -> Vector3:
	var cs := _torso_lerp(idx)
	return (cs[0] as Vector3) + _radial(ang) * (float(cs[1]) * mult)

# ------------------------------------------------------------------- torso

func _torso() -> void:
	m.begin(["Hips", "Spine*"], "skin", 1.0)
	var path := []
	var radii := []
	for e in TORSO:
		path.append(e[0])
		radii.append(e[1])
	# Wider across than deep: a standing ribcage, not a barrel.
	var sq := []
	for i in path.size():
		sq.append(TORSO_SQUASH)
	m.tube(path, radii, _s(8), 0.0, 1.0, true, true, sq, 0.55)

## Torn flesh down the sternum giving way to raw belly toward the pelvis,
## as a narrow strip of decal quads riding just proud of the hide.
func _ventral() -> void:
	var cols := [PI - 0.78, PI - 0.26, PI + 0.26, PI + 0.78]
	var pts := []
	for i in TORSO.size():
		var row := []
		for a in cols:
			row.append(_torso_shell(float(i), a, 0.007))
		pts.append(row)

	for seg in range(TORSO.size() - 1):
		# Upper half is open chest wound, lower half thin discoloured belly.
		var chest := seg >= 3
		m.begin(["Hips", "Spine*"], "gore" if chest else "belly", 0.66)
		for col in range(cols.size() - 1):
			var a: Vector3 = pts[seg][col]
			var b: Vector3 = pts[seg][col + 1]
			var c: Vector3 = pts[seg + 1][col + 1]
			var d: Vector3 = pts[seg + 1][col]
			var uu0 := float(col) / float(cols.size() - 1)
			var uu1 := float(col + 1) / float(cols.size() - 1)
			var vv0 := float(seg) / float(TORSO.size() - 1)
			var vv1 := float(seg + 1) / float(TORSO.size() - 1)
			m.quad(a, b, c, d, m.u(uu0, vv0), m.u(uu1, vv0), m.u(uu1, vv1), m.u(uu0, vv1),
				_radial(PI).normalized())

## Raw flesh laid across the flank underneath the ribs, so the gaps between
## them read as an open wound rather than clean hide. Without this the cage
## looks like pale slats stuck onto the outside of the body.
func _rib_bed() -> void:
	for side in [1.0, -1.0]:
		m.begin(["Spine2", "Spine3", "Spine4", "Spine5"], "gore", 0.70)
		var a0: float = 0.72 * side
		var a1: float = 2.14 * side
		for seg in 3:
			var i0 := 2.45 + float(seg) * 0.72
			var i1 := 2.45 + float(seg + 1) * 0.72
			for k in 3:
				var b0 := lerpf(a0, a1, float(k) / 3.0)
				var b1 := lerpf(a0, a1, float(k + 1) / 3.0)
				m.quad(
					_torso_shell(i0, b0, 0.004), _torso_shell(i0, b1, 0.004),
					_torso_shell(i1, b1, 0.004), _torso_shell(i1, b0, 0.004),
					m.u(float(k) / 3.0, float(seg) / 3.0), m.u(float(k + 1) / 3.0, float(seg) / 3.0),
					m.u(float(k + 1) / 3.0, float(seg + 1) / 3.0), m.u(float(k) / 3.0, float(seg + 1) / 3.0),
					_radial((b0 + b1) * 0.5).normalized())

## Five ribs a side, swept round the cross-section and standing proud across
## the flank so the cage reads in silhouette.
func _ribcage() -> void:
	var angs := [0.45, 1.02, 1.58, 2.08, 2.42]
	# Push tapers off at both ends: the ribs sink into the hide at the spine
	# and at the sternum, and only stand proud across the flank.
	var mult := [1.005, 1.020, 1.032, 1.018, 0.965]
	for side in [1.0, -1.0]:
		for i in 5:
			if lod == 1 and i == 4:
				continue
			if lod >= 2 and i % 2 == 1:
				continue
			m.begin(["Spine2", "Spine3", "Spine4", "Spine5"], "rib", 0.90)
			var idx := 2.35 + float(i) * 0.64
			var path := []
			for ai in angs.size():
				var p := _torso_shell_mult(idx, angs[ai] * side, mult[ai])
				p.y -= angs[ai] / PI * 0.085   # ribs slope down toward the sternum
				path.append(p)
			# Third rib back is snapped short -- cracked/missing, per the brief.
			if i == 2 and side > 0.0:
				path.resize(4)
			var radii := [0.016, 0.024, 0.027, 0.022, 0.012]
			radii.resize(path.size())
			m.tube(path, radii, 3, 0.0, 1.0, true, true, [], 0.0)

## Torn patches around the flanks, chest and haunch.
func _wounds() -> void:
	# [idx up the torso, angle from the spine ridge, half-width rad, half-height idx]
	var patches := [
		[3.10, 1.55, 0.62, 0.55], [4.55, 1.05, 0.52, 0.45],
		[1.60, 1.42, 0.58, 0.50], [3.90, 2.15, 0.50, 0.42],
		[2.35, 2.55, 0.46, 0.40], [5.10, 0.72, 0.44, 0.34],
	]
	for i in patches.size():
		var side := 1.0 if i % 2 == 0 else -1.0
		var idx: float = patches[i][0]
		var ang: float = patches[i][1] * side
		var hw: float = patches[i][2]
		var hh: float = patches[i][3]
		m.begin(["Hips", "Spine*"], "wound", 0.82)
		m.quad(
			_torso_shell(idx - hh, ang - hw, 0.006), _torso_shell(idx - hh, ang + hw, 0.006),
			_torso_shell(idx + hh, ang + hw, 0.006), _torso_shell(idx + hh, ang - hw, 0.006),
			m.u(0, 0), m.u(1, 0), m.u(1, 1), m.u(0, 1), _radial(ang).normalized())

# -------------------------------------------------------------------- neck

func _neck() -> void:
	m.begin(["Spine5", "Neck1", "Neck2", "Head"], "sinew", 0.94)
	m.tube([
		_bp("Spine5") + Vector3(0, -0.06, 0.02),
		_bp("Neck1"),
		_bp("Neck2"),
		_bp("Head") + Vector3(0, -0.01, 0.01),
	], [0.118, 0.092, 0.080, 0.082], _s(6), 0.0, 1.0, false, false, [], 0.30)

# ------------------------------------------------------------------- skull

## All skull geometry is authored as offsets from the Head bone, so moving the
## head in the rig can never leave the face behind.
func _skull() -> void:
	var h := _bp("Head")

	m.begin(["Head"], "skull", 0.98)
	m.box(h + Vector3(0, 0.008, -0.035), Vector3(0.188, 0.168, 0.195))
	m.box(h + Vector3(0, 0.044, -0.096), Vector3(0.168, 0.087, 0.119))

	m.begin(["Head"], "face", 1.0)
	m.tube([
		h + Vector3(0, 0.002, -0.088),
		h + Vector3(0, -0.014, -0.205),
		h + Vector3(0, -0.032, -0.322),
	], [0.082, 0.069, 0.055], _s(6), 0.0, 1.0, true, true, [], 0.0)
	m.box(h + Vector3(0, -0.044, -0.344), Vector3(0.094, 0.065, 0.054))

	# Lower jaw dropped to a full gape. The hinge stays put, so the Jaw bone
	# still closes the mouth when an animation rotates it back up.
	m.begin(["Jaw"], "face", 0.90)
	m.tube([
		h + Vector3(0, -0.048, -0.052),
		h + Vector3(0, -0.170, -0.150),
		h + Vector3(0, -0.292, -0.248),
	], [0.068, 0.056, 0.044], _s(5), 0.0, 1.0, true, true, [], 0.0)

	_mouth_interior()
	_teeth()
	_eyes()
	if lod < 2:
		_ears()

## Height of the jaw's upper edge at a given z offset from the Head bone --
## where the lower fangs are rooted.
func _jaw_top(z: float) -> float:
	return 0.020 + 1.367 * (z + 0.052)

## Big, uneven, badly-set fangs. Lengths vary hard, one upper tooth is missing
## and the canines overhang the jawline.
func _teeth() -> void:
	var h := _bp("Head")
	var xs := [-0.048, -0.034, -0.020, -0.007, 0.007, 0.020, 0.034, 0.048]
	var upper := [0.040, 0.055, 0.032, 0.048, 0.044, 0.0, 0.052, 0.036]
	var lower := [0.034, 0.048, 0.028, 0.044, 0.040, 0.030, 0.050, 0.033]
	var thick := [0.011, 0.013, 0.009, 0.012, 0.012, 0.010, 0.013, 0.010]
	for i in xs.size():
		if lod >= 2 and i % 2 == 1:
			continue
		var x: float = xs[i]
		if upper[i] > 0.0:
			m.begin(["Head"], "teeth", 0.95)
			var zu := -0.272 - absf(x) * 0.42
			m.cone(h + Vector3(x, -0.050, zu),
				h + Vector3(x * 1.05, -0.050 - upper[i], zu - 0.006), thick[i], 4)
		if lower[i] > 0.0:
			m.begin(["Jaw"], "teeth", 0.95)
			var zl := -0.212 - absf(x) * 0.40
			m.cone(h + Vector3(x, _jaw_top(zl) - 0.006, zl),
				h + Vector3(x * 1.05, _jaw_top(zl) + lower[i], zl - 0.006), thick[i] * 0.92, 4)
	if lod >= 2:
		return
	# Overhanging canines, one pair up and one pair down.
	for d in [-1.0, 1.0]:
		m.begin(["Head"], "teeth", 0.95)
		m.cone(h + Vector3(0.052 * d, -0.046, -0.196),
			h + Vector3(0.056 * d, -0.118, -0.206), 0.014, 4)
		m.begin(["Jaw"], "teeth", 0.95)
		var zc := -0.170
		m.cone(h + Vector3(0.050 * d, _jaw_top(zc) - 0.006, zc),
			h + Vector3(0.054 * d, _jaw_top(zc) + 0.062, zc - 0.008), 0.013, 4)

## A solid dark form filling the gape. Modelling the maw as a hollow cavity
## would need inward-facing walls and would show its own back face through the
## opening; a dark plug reads as a black throat from every angle and costs less.
func _mouth_interior() -> void:
	var h := _bp("Head")
	m.begin(["Head", "Jaw"], "mouth", 0.30)
	m.tube([
		h + Vector3(0, -0.160, -0.262),
		h + Vector3(0, -0.120, -0.170),
		h + Vector3(0, -0.075, -0.078),
	], [0.048, 0.058, 0.050], _s(6), 0.0, 1.0, true, true, [], 0.0)

## Sunken socket with a glowing block set into it, built as boxes so the eye
## reads from the front as well as the side.
func _eyes() -> void:
	var h := _bp("Head")
	for sd in [1.0, -1.0]:
		var bone := "Eye.L" if sd > 0.0 else "Eye.R"
		if lod == 0:
			m.begin(["Head"], "dark", 0.40)
			m.box(h + Vector3(0.086 * sd, 0.045, -0.100), Vector3(0.036, 0.062, 0.070))
		m.begin([bone, "Head"], "eye", 1.0)
		m.box(h + Vector3(0.096 * sd, 0.045, -0.100), Vector3(0.030, 0.046, 0.054))

func _ears() -> void:
	var h := _bp("Head")
	for sd in [1.0, -1.0]:
		m.begin(["Head"], "pelt", 0.85)
		m.card(h + Vector3(0.070 * sd, 0.050, 0.010), h + Vector3(0.150 * sd, 0.095, 0.100),
			Vector3(0.10 * sd, 0.10, 0.30).normalized(), 0.055, 0.018)

# ----------------------------------------------------------------- antlers

func _antlers() -> void:
	for s in ["L", "R"]:
		m.begin(["Antler.%s1" % s, "Antler.%s2" % s, "Antler.%s3" % s, "Head"], "antler", 1.0)
		var t3 := _bp("Antler.%s3" % s)
		var tip := t3 + (t3 - _bp("Antler.%s2" % s)).normalized() * 0.19
		m.tube([
			_bp("Antler.%s1" % s) + Vector3(0, -0.03, 0.02),
			_bp("Antler.%s1" % s),
			_bp("Antler.%s2" % s),
			t3,
			tip,
		], [0.036, 0.031, 0.024, 0.016, 0.006], _s(5), 0.0, 1.0, true, true, [], 0.34)

	# Left carries three clean points; right carries two plus a snapped stub,
	# so the rack is asymmetric the way a real one is.
	var tines := [
		["L", Vector3(0.155, 2.825, -0.425), Vector3(0.115, 2.990, -0.620), 0.017],
		["L", Vector3(0.255, 3.070, -0.332), Vector3(0.248, 3.305, -0.490), 0.015],
		["L", Vector3(0.298, 3.190, -0.262), Vector3(0.418, 3.355, -0.310), 0.013],
		["R", Vector3(-0.145, 2.815, -0.418), Vector3(-0.105, 3.000, -0.598), 0.017],
		["R", Vector3(-0.262, 3.060, -0.280), Vector3(-0.312, 3.278, -0.398), 0.015],
		["R", Vector3(-0.310, 3.132, -0.206), Vector3(-0.368, 3.202, -0.188), 0.014],  # snapped
	]
	for t in tines:
		var s: String = t[0]
		m.begin(["Antler.%s1" % s, "Antler.%s2" % s, "Antler.%s3" % s], "antler", 1.0)
		m.cone(t[1], t[2], t[3], 4)

# -------------------------------------------------------------------- arms

func _arms() -> void:
	for s in ["L", "R"]:
		m.begin(["Spine5", "Clavicle.%s" % s, "UpperArm.%s" % s,
			"Forearm1.%s" % s, "Forearm2.%s" % s, "Hand.%s" % s], "skinlimb", 0.95)
		m.tube([
			_bp("Clavicle.%s" % s),
			_bp("UpperArm.%s" % s),
			_bp("Forearm1.%s" % s),
			_bp("Forearm2.%s" % s),
			_bp("Hand.%s" % s),
		], [0.128, 0.086, 0.056, 0.046, 0.041], _s(6), 0.0, 1.0, false, false, [], 0.45)
		_hand(s)

func _hand(s: String) -> void:
	var wrist := _bp("Hand.%s" % s)
	# Palm hangs vertically now, so it is tall and thin rather than a flat pad.
	m.begin(["Hand.%s" % s, "Forearm2.%s" % s], "skinlimb", 0.90)
	m.box(wrist + Vector3(0, -0.038, -0.014), Vector3(0.120, 0.092, 0.052))

	for f in 5:
		if lod == 1 and f == 0:
			continue
		if lod >= 2 and (f == 0 or f == 4):
			continue
		var j0 := _bp("Finger%d_0.%s" % [f, s])
		var j1 := _bp("Finger%d_1.%s" % [f, s])
		var j2 := _bp("Finger%d_2.%s" % [f, s])
		var tail := Vector3.ZERO
		for b in bones:
			if b["name"] == "Finger%d_2.%s" % [f, s]:
				tail = b["tail"]
		var wl := ["Hand.%s" % s, "Finger%d_0.%s" % [f, s],
			"Finger%d_1.%s" % [f, s], "Finger%d_2.%s" % [f, s]]
		m.begin(wl, "skinlimb", 0.88)
		m.tube([j0, j1, j2], [0.022, 0.018, 0.014], _s(4), 0.0, 1.0, true, false, [], 0.0)
		m.begin(wl, "claw", 0.92)
		m.cone(j2, tail, 0.014, 4)

# -------------------------------------------------------------------- legs

func _legs() -> void:
	for s in ["L", "R"]:
		m.begin(["Hips", "Thigh.%s" % s, "Shin.%s" % s, "Hock.%s" % s,
			"Foot.%s" % s, "Toe.%s" % s], "skinlimb", 0.95)
		m.tube([
			_bp("Thigh.%s" % s) + Vector3(0, 0.052, 0.026),
			_bp("Thigh.%s" % s),
			_bp("Shin.%s" % s),
			_bp("Hock.%s" % s),
			_bp("Foot.%s" % s),
			_bp("Toe.%s" % s),
		], [0.132, 0.156, 0.094, 0.060, 0.048, 0.038], _s(6), 0.0, 1.0, false, false, [], 0.50)
		_foot(s)

## Cloven hoof-claw hybrid: two forward claws plus a raised dewclaw behind.
func _foot(s: String) -> void:
	var toe := _bp("Toe.%s" % s)
	var mul := 1.0 if s == "L" else -1.0
	m.begin(["Toe.%s" % s, "Foot.%s" % s], "hoof", 0.80)
	for d in [-1.0, 1.0]:
		m.cone(toe + Vector3(0.022 * d * mul, 0.010, -0.008),
			toe + Vector3(0.028 * d * mul, -0.018, -0.112), 0.026, 4)
	if lod >= 1:
		return
	var db := toe + Vector3(0.0, 0.058, 0.052)
	m.cone(db, db + Vector3(0.0, -0.046, 0.060), 0.016, 4)

# ------------------------------------------------------------------- blood

## Wet blood as narrow vertical runs. A single wide quad reads as a flat card
## stuck to the model; several thin ones of uneven length read as drips.
func _blood() -> void:
	var h := _bp("Head")

	# Off the lower jaw.
	m.begin(["Jaw", "Head"], "blood", 0.92)
	for i in 3:
		var x := (float(i) - 1.0) * 0.026
		var ln := 0.050 + float(i % 2) * 0.034
		m.plane(h + Vector3(x, -0.232 - ln * 0.5, -0.238),
			Vector3(0.011, 0, 0), Vector3(0, ln * 0.5, 0.004), Vector3(0, 0.12, -1).normalized())

	# Down the throat.
	m.begin(["Neck1", "Neck2", "Head"], "blood", 0.92)
	var n := _bp("Neck2")
	for i in 3:
		var x2 := (float(i) - 1.0) * 0.030
		var ln2 := 0.075 + float((i + 1) % 2) * 0.040
		m.plane(n + Vector3(x2, 0.010 - ln2 * 0.5, -0.086),
			Vector3(0.013, 0, 0), Vector3(0, ln2 * 0.5, 0.006), Vector3(0, 0.10, -1).normalized())

	# Sheeting down the open sternum.
	m.begin(["Spine*"], "blood", 0.88)
	for i in 4:
		var ang := (PI - 0.30) + float(i) * 0.20
		var top := 5.45 - float(i % 2) * 0.55
		var bot := top - 1.15 - float(i % 3) * 0.45
		m.quad(
			_torso_shell(bot, ang - 0.075, 0.010), _torso_shell(bot, ang + 0.075, 0.010),
			_torso_shell(top, ang + 0.075, 0.010), _torso_shell(top, ang - 0.075, 0.010),
			m.u(0, 1), m.u(1, 1), m.u(1, 0), m.u(0, 0), _radial(ang).normalized())

	# Slicking the hands.
	for sd in ["L", "R"]:
		m.begin(["Hand.%s" % sd, "Forearm2.%s" % sd], "blood", 0.88)
		var w := _bp("Hand.%s" % sd)
		for i in 2:
			m.plane(w + Vector3((float(i) - 0.5) * 0.042, -0.048, -0.030),
				Vector3(0.014, 0, 0), Vector3(0, 0.040, 0), Vector3(0, 0, -1))

# --------------------------------------------------------------------- fur

func _fur() -> void:
	# Heavy coat panel over the shoulders and upper back.
	m.begin(["Spine*"], "pelt", 0.95)
	var angs := [-0.66, -0.40, -0.13, 0.13, 0.40, 0.66]
	for seg in range(3, 6):
		for a in range(angs.size() - 1):
			var a0: float = angs[a]
			var a1: float = angs[a + 1]
			var am := (a0 + a1) * 0.5
			m.quad(
				_torso_shell(float(seg), a0, 0.008), _torso_shell(float(seg), a1, 0.008),
				_torso_shell(float(seg + 1), a1, 0.008), _torso_shell(float(seg + 1), a0, 0.008),
				m.u(0, 0), m.u(1, 0), m.u(1, 1), m.u(0, 1), _radial(am).normalized())

	# Mane running down the spine ridge, leaning back off the body.
	m.begin(["Spine*"], "furcard", 0.95)
	for i in 9:
		if lod >= 1 and i % 2 == 1:
			continue
		var idx := 1.6 + float(i) * 0.54
		var jig := sin(float(i) * 2.9 + 1.3) * 0.5 + 0.5
		var lean := sin(float(i) * 1.7) * 0.20
		var root := _torso_shell(idx, lean * 0.4, -0.004)
		m.card(root, root + Vector3(lean * 0.04, 0.026 + jig * 0.026, 0.048 + jig * 0.034),
			Vector3(0, 1, 0), 0.060 + jig * 0.028, 0.030 + jig * 0.020)

	# Ruff around the neck.
	m.begin(["Neck1", "Neck2", "Spine5", "Head"], "furcard", 0.95)
	for i in 6:
		if lod >= 1 and i % 2 == 1:
			continue
		var t := float(i) / 5.0
		var base: Vector3 = _bp("Spine5").lerp(_bp("Neck2"), t)
		var root2 := base + Vector3(0, 0.020, 0.058)
		m.card(root2, root2 + Vector3(0, 0.030, 0.062), Vector3(1, 0, 0), 0.052, 0.020)

	# Sparse clumps on the shoulders and haunches.
	for sd in [1.0, -1.0]:
		var sn := "L" if sd > 0.0 else "R"
		m.begin(["Clavicle.%s" % sn, "UpperArm.%s" % sn, "Spine5"], "furcard", 0.92)
		var sh: Vector3 = _bp("Clavicle.%s" % sn).lerp(_bp("UpperArm.%s" % sn), 0.55)
		for i in 4:
			var root4 := sh + Vector3(0.026 * sd * float(i) - 0.026 * sd,
				0.052 - float(i) * 0.056, 0.026 + 0.014 * float(i))
			m.card(root4, root4 + Vector3(0.032 * sd, 0.030, 0.052), Vector3(0, 1, 0), 0.048, 0.016)
		m.begin(["Hips", "Spine1", "Thigh.%s" % sn], "furcard", 0.92)
		for i in 3:
			var root5 := _torso_shell(0.5 + float(i) * 0.45, 0.9 * sd, -0.004)
			m.card(root5, root5 + Vector3(0.030 * sd, 0.024, 0.048), Vector3(0, 1, 0), 0.052, 0.018)
