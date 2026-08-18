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

const FINGER_SEG := [0.140, 0.115, 0.095]   # proximal, middle, distal(claw)

## Spread of each finger knuckle from the wrist, in hand-local space
## (x = across the palm, y = up, z = forward). Thumb sits back and inboard.
const FINGER_BASE := [
	Vector3(0.058, -0.004, 0.038),
	Vector3(0.035, -0.010, -0.030),
	Vector3(0.010, -0.012, -0.048),
	Vector3(-0.015, -0.010, -0.040),
	Vector3(-0.040, -0.005, -0.014),
]

## Per-joint curl. The arms hang now rather than taking weight, so the fingers
## drop nearly straight down and hook forward at the claw.
const FINGER_DIR := [
	Vector3(0.0, -0.90, -0.44),
	Vector3(0.0, -0.96, -0.28),
	Vector3(0.0, -0.99, -0.12),
]

## Returns an ordered bone list (parents always precede children).
## Each entry: {name, parent, pos, tail} -- tail is the skinning end point,
## defaulting to the first child's position when omitted.
static func build() -> Array:
	var b: Array = []

	var add := func(n: String, p: String, pos: Vector3, tail = null) -> void:
		b.append({"name": n, "parent": p, "pos": pos, "tail": tail})

	# ---- spine: upright now, not slung horizontally. The column runs bottom to
	# top with a forward lean, keeping the permanent hunch while the creature
	# stands its full height (~3.4m to the antler tips).
	add.call("Hips", "", Vector3(0.0, 1.820, 0.130))
	add.call("Spine1", "Hips", Vector3(0.0, 1.965, 0.100))
	add.call("Spine2", "Spine1", Vector3(0.0, 2.105, 0.062))
	add.call("Spine3", "Spine2", Vector3(0.0, 2.240, 0.012))
	add.call("Spine4", "Spine3", Vector3(0.0, 2.365, -0.048))
	add.call("Spine5", "Spine4", Vector3(0.0, 2.470, -0.122))

	# ---- neck and head: thrust forward off the top of the column
	add.call("Neck1", "Spine5", Vector3(0.0, 2.550, -0.212))
	add.call("Neck2", "Neck1", Vector3(0.0, 2.610, -0.335))
	add.call("Head", "Neck2", Vector3(0.0, 2.640, -0.460))
	add.call("Jaw", "Head", Vector3(0.0, 2.592, -0.512), Vector3(0.0, 2.385, -0.718))
	add.call("Eye.L", "Head", Vector3(0.069, 2.680, -0.552), Vector3(0.069, 2.680, -0.572))
	add.call("Eye.R", "Head", Vector3(-0.069, 2.680, -0.552), Vector3(-0.069, 2.680, -0.572))

	# ---- antlers: 3-bone chains, deliberately mismatched left to right
	add.call("Antler.L1", "Head", Vector3(0.090, 2.722, -0.448))
	add.call("Antler.L2", "Antler.L1", Vector3(0.235, 2.990, -0.388))
	add.call("Antler.L3", "Antler.L2", Vector3(0.312, 3.246, -0.208), Vector3(0.357, 3.396, -0.103))
	add.call("Antler.R1", "Head", Vector3(-0.090, 2.722, -0.448))
	add.call("Antler.R2", "Antler.R1", Vector3(-0.210, 2.960, -0.344))
	add.call("Antler.R3", "Antler.R2", Vector3(-0.338, 3.186, -0.144), Vector3(-0.413, 3.318, -0.027))

	# ---- arms: hanging free now. Still grossly elongated -- 2.26m of chain
	#      against 2.02m of leg -- so the claws swing below the knee.
	for s in ["L", "R"]:
		var m := 1.0 if s == "L" else -1.0
		add.call("Clavicle.%s" % s, "Spine5", Vector3(0.082 * m, 2.452, -0.098))
		add.call("UpperArm.%s" % s, "Clavicle.%s" % s, Vector3(0.255 * m, 2.415, -0.075))
		add.call("Forearm1.%s" % s, "UpperArm.%s" % s, Vector3(0.320 * m, 1.720, -0.160))
		add.call("Forearm2.%s" % s, "Forearm1.%s" % s, Vector3(0.355 * m, 1.180, -0.245))
		add.call("Hand.%s" % s, "Forearm2.%s" % s, Vector3(0.375 * m, 0.680, -0.330))

		var wrist := Vector3(0.375 * m, 0.680, -0.330)
		for f in 5:
			var base: Vector3 = FINGER_BASE[f]
			var knuckle := wrist + Vector3(base.x * m, base.y, base.z)
			var prev := knuckle
			var parent := "Hand.%s" % s
			for j in 3:
				var jn := "Finger%d_%d.%s" % [f, j, s]
				var nxt: Vector3 = prev + (FINGER_DIR[j] as Vector3).normalized() * float(FINGER_SEG[j])
				add.call(jn, parent, prev, nxt if j == 2 else null)
				parent = jn
				prev = nxt

	# ---- legs: digitigrade, extended to carry the standing height, with the
	#      reversed hock still doing the work
	for s in ["L", "R"]:
		var m := 1.0 if s == "L" else -1.0
		add.call("Thigh.%s" % s, "Hips", Vector3(0.155 * m, 1.790, 0.100))
		add.call("Shin.%s" % s, "Thigh.%s" % s, Vector3(0.175 * m, 1.195, -0.045))
		add.call("Hock.%s" % s, "Shin.%s" % s, Vector3(0.180 * m, 0.620, 0.175))
		add.call("Foot.%s" % s, "Hock.%s" % s, Vector3(0.180 * m, 0.185, 0.020))
		add.call("Toe.%s" % s, "Foot.%s" % s, Vector3(0.180 * m, 0.020, -0.170), Vector3(0.180 * m, 0.0, -0.275))

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
