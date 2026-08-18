extends RefCounted
## Assembles the Skinwalker body from the rig, part by part.
##
## Every landmark below is read off the concept art: pelvis low and set back,
## ribcage the widest point of a body that is otherwise starved hollow, a
## ventral strip of torn flesh running from sternum to gut, arms that reach
## the ground, and hind legs with a real reversed hock.

const Atlas := preload("res://tools/sw_atlas.gd")

## Torso is a tube slung BELOW the spine bones -- the backbone rides the top
## of the ribcage, it is not the centreline of the body.
const TORSO := [
	# [centre, radius] -- each entry's top touches its spine bone, while the
	# underside is authored as a deep chest tucking up hard into a starved
	# waist, greyhound-fashion.
	[Vector3(0, 1.262, 0.440), 0.138],   # pelvis
	[Vector3(0, 1.335, 0.280), 0.120],   # waist, tucked up and pinched in
	[Vector3(0, 1.330, 0.160), 0.180],
	[Vector3(0, 1.323, 0.040), 0.233],
	[Vector3(0, 1.332, -0.085), 0.257],  # ribcage, widest point
	[Vector3(0, 1.353, -0.210), 0.243],
	[Vector3(0, 1.393, -0.330), 0.168],  # chest front
]

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
	_ribcage()
	_neck()
	_wounds()
	_skull()
	_antlers()
	_arms()
	_legs()
	if lod < 2:
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

# ------------------------------------------------------------------- torso

func _torso() -> void:
	m.begin(["Hips", "Spine*"], "skin", 1.0)
	var path := []
	var radii := []
	for e in TORSO:
		path.append(e[0])
		radii.append(e[1])
	# Slightly flattened side-to-side: a starved ribcage is a deep, narrow keel.
	var sq := []
	for i in path.size():
		sq.append(Vector2(1.0, 0.92))
	m.tube(path, radii, _s(8), 0.0, 1.0, true, true, sq, 0.55)

## Torn flesh down the sternum, giving way to raw belly toward the pelvis.
## Built as a narrow strip of decal quads riding just proud of the hide.
func _ventral() -> void:
	var cols := [-0.80, -0.27, 0.27, 0.80]  # radians either side of straight down
	var pts := []
	for e in TORSO:
		var c: Vector3 = e[0]
		var r: float = e[1]
		var row := []
		for a in cols:
			row.append(c + Vector3(sin(a) * r, -cos(a) * r, 0.0) * 1.015)
		pts.append(row)

	# Front of the strip (sternum, z negative) is open wound; the run back
	# toward the pelvis is thin, discoloured belly skin.
	for seg in range(TORSO.size() - 1):
		var front := seg >= 3
		m.begin(["Hips", "Spine*"], "gore" if front else "belly", 0.62)
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
				Vector3(0, -1, 0))

## Interpolate the torso cross-section at a given z -> [centre_y, radius].
func _torso_cs(z: float) -> Array:
	var lo := 0
	for i in range(TORSO.size() - 1):
		if z <= float((TORSO[i][0] as Vector3).z) and z >= float((TORSO[i + 1][0] as Vector3).z):
			lo = i
			break
	var z0 := float((TORSO[lo][0] as Vector3).z)
	var z1 := float((TORSO[lo + 1][0] as Vector3).z)
	var t := 0.0 if is_equal_approx(z0, z1) else clampf((z - z0) / (z1 - z0), 0.0, 1.0)
	return [
		lerpf(float((TORSO[lo][0] as Vector3).y), float((TORSO[lo + 1][0] as Vector3).y), t),
		lerpf(float(TORSO[lo][1]), float(TORSO[lo + 1][1]), t),
	]

## Five ribs a side, swept round the actual cage cross-section and pushed
## just proud of the hide so the cage reads in silhouette.
func _ribcage() -> void:
	var angs := [0.45, 1.02, 1.58, 2.08, 2.36]  # radians from the spine ridge
	# Push tapers off at both ends so the ribs sink back into the hide at the
	# spine and at the sternum, and only stand proud across the flank.
	var push := [1.010, 1.055, 1.075, 1.030, 0.950]
	for side in [1.0, -1.0]:
		for i in 5:
			# Thin the cage with distance but keep it spanning the full chest,
			# so the ribcage still reads in silhouette at LOD2.
			if lod == 1 and i == 4:
				continue
			if lod >= 2 and i % 2 == 1:
				continue
			m.begin(["Spine2", "Spine3", "Spine4", "Spine5"], "rib", 0.90)
			var z := -0.215 + float(i) * 0.062
			var cs := _torso_cs(z)
			var cy: float = cs[0]
			var r: float = cs[1]
			var path := []
			for ai in angs.size():
				var a: float = angs[ai]
				var pu: float = push[ai]
				path.append(Vector3(sin(a) * r * pu * side, cy + cos(a) * r * pu, z))
			# Third rib back is snapped short -- cracked/missing, per the brief.
			if i == 2 and side > 0.0:
				path.resize(4)
			var radii := [0.019, 0.030, 0.034, 0.026, 0.013]
			radii.resize(path.size())
			m.tube(path, radii, 3, 0.0, 1.0, true, true, [], 0.0)

## Torn patches on the flanks and haunch. The ventral strip covers the sternum
## and gut, but none of that reads from a 3/4 view -- these do.
func _wounds() -> void:
	# [segment along the torso, angle from the ridge, half-width in radians,
	#  half-height in torso segments] -- both are parametric, not metres.
	var patches := [
		[2.40, 1.55, 0.62, 0.95], [4.20, 1.02, 0.50, 0.70],
		[1.10, 1.38, 0.55, 0.80], [3.50, 2.00, 0.46, 0.62],
	]
	for i in patches.size():
		var side := 1.0 if i % 2 == 0 else -1.0
		var seg: float = patches[i][0]
		var ang: float = patches[i][1] * side
		var hw: float = patches[i][2]
		var hh: float = patches[i][3]
		m.begin(["Hips", "Spine*"], "wound", 0.80)
		var p0 := _torso_shell(seg - hh, ang - hw, 0.006)
		var p1 := _torso_shell(seg - hh, ang + hw, 0.006)
		var p2 := _torso_shell(seg + hh, ang + hw, 0.006)
		var p3 := _torso_shell(seg + hh, ang - hw, 0.006)
		m.quad(p0, p1, p2, p3, m.u(0, 0), m.u(1, 0), m.u(1, 1), m.u(0, 1),
			Vector3(sin(ang), cos(ang), 0.0))

# -------------------------------------------------------------------- neck

func _neck() -> void:
	m.begin(["Spine5", "Neck1", "Neck2", "Head"], "sinew", 0.94)
	var path := [
		_bp("Spine5") + Vector3(0, -0.05, 0.02),
		_bp("Neck1"),
		_bp("Neck2"),
		_bp("Head") + Vector3(0, -0.01, 0.01),
	]
	var radii := [0.118, 0.092, 0.080, 0.082]
	m.tube(path, radii, _s(6), 0.0, 1.0, false, false, [], 0.30)

# ------------------------------------------------------------------- skull

## All skull geometry is authored as offsets from the Head bone, so moving the
## head in the rig can never leave the face behind.
func _skull() -> void:
	var h := _bp("Head")

	# Cranium and brow. The brow block is where the antler pedicles sit.
	m.begin(["Head"], "skull", 0.98)
	m.box(h + Vector3(0, 0.008, -0.035), Vector3(0.188, 0.168, 0.195))
	m.box(h + Vector3(0, 0.044, -0.096), Vector3(0.168, 0.087, 0.119))

	# Long cervine muzzle, tapering to the nose.
	m.begin(["Head"], "face", 1.0)
	m.tube([
		h + Vector3(0, 0.002, -0.088),
		h + Vector3(0, -0.014, -0.205),
		h + Vector3(0, -0.032, -0.322),
	], [0.082, 0.069, 0.055], _s(6), 0.0, 1.0, false, true, [], 0.0)
	m.box(h + Vector3(0, -0.044, -0.344), Vector3(0.094, 0.065, 0.054))

	# Lower jaw, hung open. Weighted to Jaw so it can snap independently.
	m.begin(["Jaw"], "face", 0.90)
	m.tube([
		h + Vector3(0, -0.052, -0.052),
		h + Vector3(0, -0.082, -0.170),
		h + Vector3(0, -0.102, -0.288),
	], [0.068, 0.056, 0.044], _s(5), 0.0, 1.0, true, true, [], 0.0)

	_teeth()
	if lod == 0:
		_mouth_interior()
	_eyes()
	if lod < 2:
		_ears()

## Broken, uneven dentition -- lengths vary and one upper tooth is missing.
func _teeth() -> void:
	var h := _bp("Head")
	var xs := [-0.040, -0.027, -0.014, 0.0, 0.014, 0.027, 0.040]
	var upper_len := [0.020, 0.026, 0.018, 0.023, 0.0, 0.025, 0.019]  # 0 == gap
	var lower_len := [0.017, 0.022, 0.015, 0.021, 0.024, 0.016, 0.020]
	for i in xs.size():
		if lod >= 2 and i % 2 == 1:
			continue
		var x: float = xs[i]
		var zf := -0.275 - absf(x) * 0.45
		if upper_len[i] > 0.0:
			m.begin(["Head"], "teeth", 0.95)
			m.cone(h + Vector3(x, -0.050, zf),
				h + Vector3(x, -0.050 - upper_len[i], zf - 0.004), 0.0065, 4)
		if lower_len[i] > 0.0:
			m.begin(["Jaw"], "teeth", 0.95)
			var zl := -0.258 - absf(x) * 0.45
			m.cone(h + Vector3(x, -0.105, zl),
				h + Vector3(x, -0.105 + lower_len[i], zl - 0.004), 0.0060, 4)
	if lod >= 2:
		return
	# A pair of longer canines further back, one each side.
	m.begin(["Head"], "teeth", 0.95)
	for d in [-1.0, 1.0]:
		m.cone(h + Vector3(0.048 * d, -0.048, -0.190),
			h + Vector3(0.050 * d, -0.082, -0.196), 0.0075, 4)

## Dark wet interior filling the gap between the tooth rows.
func _mouth_interior() -> void:
	var h := _bp("Head")
	m.begin(["Head"], "mouth", 0.30)
	var zs := [-0.090, -0.170, -0.250, -0.300]
	for i in range(zs.size() - 1):
		var z0: float = zs[i]
		var z1: float = zs[i + 1]
		var w0 := 0.050 - float(i) * 0.006
		var w1 := 0.050 - float(i + 1) * 0.006
		m.quad(h + Vector3(-w0, -0.052, z0), h + Vector3(w0, -0.052, z0),
			h + Vector3(w1, -0.052, z1), h + Vector3(-w1, -0.052, z1),
			m.u(0, 0), m.u(1, 0), m.u(1, 1), m.u(0, 1), Vector3(0, -1, 0))
		m.quad(h + Vector3(-w0, -0.098, z0), h + Vector3(w0, -0.098, z0),
			h + Vector3(w1, -0.100, z1), h + Vector3(-w1, -0.100, z1),
			m.u(0, 0), m.u(1, 0), m.u(1, 1), m.u(0, 1), Vector3(0, 1, 0))
		for sd in [1.0, -1.0]:
			m.quad(h + Vector3(w0 * sd, -0.052, z0), h + Vector3(w1 * sd, -0.052, z1),
				h + Vector3(w1 * sd, -0.100, z1), h + Vector3(w0 * sd, -0.098, z0),
				m.u(0, 0), m.u(1, 0), m.u(1, 1), m.u(0, 1), Vector3(sd, 0, 0))

## Small, sunken, dull amber. Socket plate behind reads as a dark hollow.
func _eyes() -> void:
	var h := _bp("Head")
	for sd in [1.0, -1.0]:
		var bone := "Eye.L" if sd > 0.0 else "Eye.R"
		var c := h + Vector3(0.069 * sd, 0.040, -0.092)
		var outward := Vector3(0.80 * sd, 0.22, -0.56).normalized()
		if lod == 0:
			m.begin(["Head"], "dark", 0.45)
			m.plane(c - outward * 0.006, Vector3(0, 0, 0.030), Vector3(0, 0.026, 0), outward)
		m.begin([bone, "Head"], "eye", 1.0)
		m.plane(c + outward * 0.004, Vector3(0, 0, 0.019), Vector3(0, 0.017, 0), outward)

func _ears() -> void:
	var h := _bp("Head")
	for sd in [1.0, -1.0]:
		m.begin(["Head"], "pelt", 0.85)
		var root := h + Vector3(0.070 * sd, 0.050, 0.010)
		var tip := h + Vector3(0.150 * sd, 0.095, 0.100)
		m.card(root, tip, Vector3(0.10 * sd, 0.10, 0.30).normalized(), 0.055, 0.018)

# ----------------------------------------------------------------- antlers

func _antlers() -> void:
	# Main beams follow the 3-bone chains, tapering to a point.
	for s in ["L", "R"]:
		m.begin(["Antler.%s1" % s, "Antler.%s2" % s, "Antler.%s3" % s, "Head"], "antler", 1.0)
		var tip := _bp("Antler.%s3" % s) + (_bp("Antler.%s3" % s) - _bp("Antler.%s2" % s)).normalized() * 0.19
		m.tube([
			_bp("Antler.%s1" % s) + Vector3(0, -0.03, 0.02),
			_bp("Antler.%s1" % s),
			_bp("Antler.%s2" % s),
			_bp("Antler.%s3" % s),
			tip,
		], [0.036, 0.031, 0.024, 0.016, 0.006], _s(5), 0.0, 1.0, true, true, [], 0.34)

	# Tines. Left carries three clean points; right carries two plus a snapped
	# stub, so the rack is asymmetric the way a real one is.
	var tines := [
		["L", Vector3(0.155, 1.865, -0.555), Vector3(0.115, 2.030, -0.750), 0.017],
		["L", Vector3(0.255, 2.110, -0.462), Vector3(0.248, 2.345, -0.620), 0.015],
		["L", Vector3(0.298, 2.230, -0.392), Vector3(0.418, 2.395, -0.440), 0.013],
		["R", Vector3(-0.145, 1.855, -0.548), Vector3(-0.105, 2.040, -0.728), 0.017],
		["R", Vector3(-0.262, 2.100, -0.410), Vector3(-0.312, 2.318, -0.528), 0.015],
		["R", Vector3(-0.310, 2.172, -0.336), Vector3(-0.368, 2.242, -0.318), 0.014],  # snapped short
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
		], [0.125, 0.085, 0.056, 0.046, 0.041], _s(6), 0.0, 1.0, false, false, [], 0.45)
		_hand(s)

func _hand(s: String) -> void:
	var wrist := _bp("Hand.%s" % s)
	m.begin(["Hand.%s" % s, "Forearm2.%s" % s], "skinlimb", 0.90)
	m.box(wrist + Vector3(0, -0.016, -0.034), Vector3(0.126, 0.042, 0.100))

	for f in 5:
		# Fingers are invisible past a few metres; drop the outer ones first.
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
		m.tube([j0, j1, j2], [0.021, 0.017, 0.013], _s(4), 0.0, 1.0, true, false, [], 0.0)
		# Long hooked claw finishing each finger.
		m.begin(wl, "claw", 0.92)
		m.cone(j2, tail, 0.013, 4)

# -------------------------------------------------------------------- legs

func _legs() -> void:
	for s in ["L", "R"]:
		m.begin(["Hips", "Thigh.%s" % s, "Shin.%s" % s, "Hock.%s" % s,
			"Foot.%s" % s, "Toe.%s" % s], "skinlimb", 0.95)
		m.tube([
			_bp("Thigh.%s" % s) + Vector3(0, 0.048, 0.022),
			_bp("Thigh.%s" % s),
			_bp("Shin.%s" % s),
			_bp("Hock.%s" % s),
			_bp("Foot.%s" % s),
			_bp("Toe.%s" % s),
		], [0.112, 0.130, 0.080, 0.054, 0.044, 0.036], _s(6), 0.0, 1.0, false, false, [], 0.50)
		_foot(s)

## Cloven hoof-claw hybrid: two forward claws plus a raised dewclaw behind.
func _foot(s: String) -> void:
	var toe := _bp("Toe.%s" % s)
	var mul := 1.0 if s == "L" else -1.0
	m.begin(["Toe.%s" % s, "Foot.%s" % s], "hoof", 0.80)
	for d in [-1.0, 1.0]:
		var base := toe + Vector3(0.020 * d * mul, 0.008, -0.010)
		var tip := toe + Vector3(0.026 * d * mul, -0.020, -0.108)
		m.cone(base, tip, 0.024, 4)
	if lod >= 1:
		return
	# Dewclaw, hooked backward off the pastern.
	var db := toe + Vector3(0.0, 0.052, 0.030)
	m.cone(db, db + Vector3(0.0, -0.042, 0.056), 0.015, 4)

# --------------------------------------------------------------------- fur

## A point on the torso shell, optionally pushed out along the true radial
## normal. ang == 0 is the spine ridge.
func _torso_shell(idx: float, ang: float, push: float = 0.0) -> Vector3:
	var i := clampi(int(floor(idx)), 0, TORSO.size() - 2)
	var f := clampf(idx - float(i), 0.0, 1.0)
	var c: Vector3 = (TORSO[i][0] as Vector3).lerp(TORSO[i + 1][0], f)
	var r: float = lerpf(float(TORSO[i][1]), float(TORSO[i + 1][1]), f)
	return c + Vector3(sin(ang), cos(ang), 0.0) * (r + push)

func _fur() -> void:
	# Heavy coat panel over the withers and shoulders, laid just off the shell.
	# The push is along the radial normal -- scaling world positions instead
	# would shove the panel away from the world origin, not off the body.
	m.begin(["Spine*"], "pelt", 0.95)
	var angs := [-0.62, -0.36, -0.12, 0.12, 0.36, 0.62]
	for seg in range(3, 6):
		for a in range(angs.size() - 1):
			var a0: float = angs[a]
			var a1: float = angs[a + 1]
			var p0 := _torso_shell(float(seg), a0, 0.008)
			var p1 := _torso_shell(float(seg), a1, 0.008)
			var p2 := _torso_shell(float(seg + 1), a1, 0.008)
			var p3 := _torso_shell(float(seg + 1), a0, 0.008)
			var am := (a0 + a1) * 0.5
			m.quad(p0, p1, p2, p3, m.u(0, 0), m.u(1, 0), m.u(1, 1), m.u(0, 1),
				Vector3(sin(am), cos(am), 0.0))

	# Mane running the spine ridge: short, narrow, leaning back.
	m.begin(["Spine*"], "furcard", 0.95)
	for i in 9:
		if lod >= 1 and i % 2 == 1:
			continue
		var idx := 2.0 + float(i) * 0.48
		var lean := sin(float(i) * 1.7) * 0.22
		# Deterministic but uneven: clump height and width both wander.
		var jig := sin(float(i) * 2.9 + 1.3) * 0.5 + 0.5
		var root := _torso_shell(idx, lean * 0.4, -0.004)
		m.card(root, root + Vector3(lean * 0.05, 0.024 + jig * 0.030, 0.052 + jig * 0.034),
			Vector3(0, 0, 1), 0.062 + jig * 0.030, 0.034 + jig * 0.022)

	# Ruff along the neck crest, and a thinner hang underneath.
	m.begin(["Neck1", "Neck2", "Spine5", "Head"], "furcard", 0.95)
	for i in 6:
		if lod >= 1 and i % 2 == 1:
			continue
		var t := float(i) / 5.0
		var base: Vector3 = _bp("Spine5").lerp(_bp("Neck2"), t)
		var root2 := base + Vector3(0, 0.052, 0)
		m.card(root2, root2 + Vector3(0, 0.034, 0.052), Vector3(0, 0, 1), 0.046, 0.020)
	for i in 3:
		var t2 := float(i) / 2.0
		var base2: Vector3 = _bp("Neck1").lerp(_bp("Head"), t2)
		var root3 := base2 + Vector3(0, -0.046, 0)
		m.card(root3, root3 + Vector3(0, -0.052, 0.026), Vector3(0, 0, 1), 0.038, 0.014)

	# Sparse clumps on the shoulders and haunches, keyed off the bones so they
	# follow any later change to the rig.
	for sd in [1.0, -1.0]:
		var sn := "L" if sd > 0.0 else "R"
		m.begin(["Clavicle.%s" % sn, "UpperArm.%s" % sn, "Spine5"], "furcard", 0.92)
		var sh: Vector3 = _bp("Clavicle.%s" % sn).lerp(_bp("UpperArm.%s" % sn), 0.55)
		for i in 4:
			var root4 := sh + Vector3(0.030 * sd * float(i) - 0.030 * sd, 0.060 - float(i) * 0.058, 0.010 * float(i))
			m.card(root4, root4 + Vector3(0.048 * sd, 0.058, 0.016), Vector3(0, 0, 1), 0.042, 0.014)
		m.begin(["Hips", "Spine1", "Thigh.%s" % sn], "furcard", 0.92)
		var hp := _bp("Hips")
		for i in 3:
			var root5 := hp + Vector3(0.105 * sd, 0.015 - float(i) * 0.048, -0.130 + float(i) * 0.042)
			m.card(root5, root5 + Vector3(0.026 * sd, 0.058, 0.030), Vector3(0, 0, 1), 0.046, 0.016)
