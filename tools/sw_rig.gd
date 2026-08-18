extends RefCounted
## Skinwalker skeleton definition.
##
## Bones are authored by GLOBAL rest position; the builder derives each local
## offset from its parent. Rest bases are left as identity on purpose -- with
## no baked rest rotation, an animation curve on a bone is a plain world-axis
## euler ("bend the elbow about X"), which keeps the hand-authored poses in
## sw_anim.gd readable instead of turning them into quaternion soup.
##
## Convention follows the rig this replaces: facing -Z, +X is the ".L" side.
##
## Proportions come off the concept art: arms measurably longer than the legs
## (1.97m vs 1.84m along the chain), pelvis low and back, withers raised, head
## carried forward on a long neck, digitigrade hind legs with a true reversed
## hock, and hands planted at ground level for the semi-quadrupedal stance.

const FINGER_SEG := [0.130, 0.105, 0.085]   # proximal, middle, distal(claw)

## Spread of each finger knuckle from the wrist, in hand-local space
## (x = across the palm, y = up, z = forward). Thumb sits back and inboard.
const FINGER_BASE := [
	Vector3(0.055, -0.005, 0.035),
	Vector3(0.034, -0.012, -0.030),
	Vector3(0.010, -0.014, -0.048),
	Vector3(-0.014, -0.012, -0.040),
	Vector3(-0.038, -0.006, -0.014),
]

## Per-joint curl direction. Fingers reach forward then hook down, so the
## claw tips plant on the ground under the creature's weight.
const FINGER_DIR := [
	Vector3(0.0, -0.55, -0.84),
	Vector3(0.0, -0.80, -0.60),
	Vector3(0.0, -0.95, -0.32),
]

## Returns an ordered bone list (parents always precede children).
## Each entry: {name, parent, pos, tail} -- tail is the skinning end point,
## defaulting to the first child's position when omitted.
static func build() -> Array:
	var b: Array = []

	var add := func(n: String, p: String, pos: Vector3, tail = null) -> void:
		b.append({"name": n, "parent": p, "pos": pos, "tail": tail})

	# ---- spine: pelvis low and back, arcing up to a raised withers hump.
	# Hip height is ~57% of total, torso ~30% of it: the balance the concept
	# art actually shows, rather than the all-legs read a taller hip gives.
	add.call("Hips", "", Vector3(0.0, 1.400, 0.400))
	add.call("Spine1", "Hips", Vector3(0.0, 1.455, 0.280))
	add.call("Spine2", "Spine1", Vector3(0.0, 1.510, 0.160))
	add.call("Spine3", "Spine2", Vector3(0.0, 1.556, 0.040))
	add.call("Spine4", "Spine3", Vector3(0.0, 1.588, -0.085))
	add.call("Spine5", "Spine4", Vector3(0.0, 1.596, -0.210))

	# ---- neck and head: long, thin, carried forward and down
	add.call("Neck1", "Spine5", Vector3(0.0, 1.585, -0.330))
	add.call("Neck2", "Neck1", Vector3(0.0, 1.628, -0.470))
	add.call("Head", "Neck2", Vector3(0.0, 1.680, -0.590))
	add.call("Jaw", "Head", Vector3(0.0, 1.632, -0.642), Vector3(0.0, 1.590, -0.900))
	add.call("Eye.L", "Head", Vector3(0.069, 1.720, -0.682), Vector3(0.069, 1.720, -0.702))
	add.call("Eye.R", "Head", Vector3(-0.069, 1.720, -0.682), Vector3(-0.069, 1.720, -0.702))

	# ---- antlers: 3-bone chains, deliberately mismatched left to right
	add.call("Antler.L1", "Head", Vector3(0.090, 1.762, -0.578))
	add.call("Antler.L2", "Antler.L1", Vector3(0.235, 2.030, -0.518))
	add.call("Antler.L3", "Antler.L2", Vector3(0.312, 2.286, -0.338), Vector3(0.357, 2.436, -0.233))
	add.call("Antler.R1", "Head", Vector3(-0.090, 1.762, -0.578))
	add.call("Antler.R2", "Antler.R1", Vector3(-0.210, 2.000, -0.474))
	add.call("Antler.R3", "Antler.R2", Vector3(-0.338, 2.226, -0.274), Vector3(-0.413, 2.358, -0.157))

	# ---- arms: grossly elongated, forearm split in two so the long span
	#      cannot pinch, wrists carried down at ground level
	for s in ["L", "R"]:
		var m := 1.0 if s == "L" else -1.0
		add.call("Clavicle.%s" % s, "Spine5", Vector3(0.078 * m, 1.578, -0.182))
		add.call("UpperArm.%s" % s, "Clavicle.%s" % s, Vector3(0.238 * m, 1.545, -0.160))
		add.call("Forearm1.%s" % s, "UpperArm.%s" % s, Vector3(0.318 * m, 1.000, -0.300))
		add.call("Forearm2.%s" % s, "Forearm1.%s" % s, Vector3(0.348 * m, 0.585, -0.430))
		add.call("Hand.%s" % s, "Forearm2.%s" % s, Vector3(0.368 * m, 0.240, -0.560))

		var wrist := Vector3(0.368 * m, 0.240, -0.560)
		for f in 5:
			var base: Vector3 = FINGER_BASE[f]
			var knuckle := wrist + Vector3(base.x * m, base.y, base.z)
			var prev := knuckle
			var parent := "Hand.%s" % s
			for j in 3:
				var jn := "Finger%d_%d.%s" % [f, j, s]
				var nxt: Vector3 = prev + (FINGER_DIR[j] as Vector3).normalized() * float(FINGER_SEG[j])
				# Leaf claw carries an explicit tail so skinning has a real span.
				add.call(jn, parent, prev, nxt if j == 2 else null)
				parent = jn
				prev = nxt

	# ---- legs: digitigrade with a genuine reversed hock between knee and ankle
	for s in ["L", "R"]:
		var m := 1.0 if s == "L" else -1.0
		add.call("Thigh.%s" % s, "Hips", Vector3(0.150 * m, 1.375, 0.355))
		add.call("Shin.%s" % s, "Thigh.%s" % s, Vector3(0.172 * m, 0.900, 0.185))
		add.call("Hock.%s" % s, "Shin.%s" % s, Vector3(0.178 * m, 0.470, 0.375))
		add.call("Foot.%s" % s, "Hock.%s" % s, Vector3(0.178 * m, 0.145, 0.215))
		add.call("Toe.%s" % s, "Foot.%s" % s, Vector3(0.178 * m, 0.018, 0.020), Vector3(0.178 * m, 0.0, -0.085))

	return b

## Resolve each bone's tail: explicit if given, else the first child's head,
## else extend along the parent direction so leaf bones still have a span.
static func resolve_tails(bones: Array) -> void:
	var idx := {}
	for i in bones.size():
		idx[bones[i]["name"]] = i
	for i in bones.size():
		if bones[i]["tail"] != null:
			continue
		var child_pos = null
		for j in bones.size():
			if bones[j]["parent"] == bones[i]["name"]:
				child_pos = bones[j]["pos"]
				break
		if child_pos != null:
			bones[i]["tail"] = child_pos
		else:
			var par: String = bones[i]["parent"]
			var dir := Vector3(0, -0.1, 0)
			if par != "" and idx.has(par):
				dir = (bones[i]["pos"] - bones[idx[par]]["pos"])
				dir = dir.normalized() * 0.08 if dir.length() > 0.0001 else Vector3(0, -0.08, 0)
			bones[i]["tail"] = bones[i]["pos"] + dir
