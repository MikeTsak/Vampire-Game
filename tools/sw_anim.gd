extends RefCounted
## The nine-clip animation set for the Skinwalker.
##
## Curves are authored as functions of cycle phase and then sampled onto
## keyframes at a deliberately low rate with LINEAR interpolation. That is the
## period-correct choice the brief asks for: at 12 keys a second the motion
## carries a faint snap instead of the glassy smoothness modern spline
## interpolation would give it.
##
## Bone rest bases are identity (see sw_rig.gd), so every rotation below is a
## plain world-axis euler in DEGREES: +X pitches a limb forward, +Y yaws,
## +Z rolls sideways.

const SKEL := "MeshBase/Skeleton3D"
const KEY_FPS := 12.0

var rest: Dictionary = {}   # bone name -> local rest position

func setup(bones: Array) -> void:
	var idx := {}
	for i in bones.size():
		idx[bones[i]["name"]] = i
	for b in bones:
		var local: Vector3 = b["pos"]
		if b["parent"] != "":
			local -= bones[idx[b["parent"]]]["pos"]
		rest[b["name"]] = local

# ------------------------------------------------------------------ helpers

func _anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	a.step = 1.0 / KEY_FPS
	return a

## Sample `fn(phase) -> Vector3` (euler degrees) onto a rotation track.
func rot(a: Animation, bone: String, fn: Callable) -> void:
	var ti := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(ti, NodePath("%s:%s" % [SKEL, bone]))
	a.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
	var n := maxi(2, int(round(a.length * KEY_FPS)))
	for i in n + 1:
		var p := float(i) / float(n)
		var e: Vector3 = fn.call(p)
		a.rotation_track_insert_key(ti, p * a.length, Quaternion.from_euler(e * (PI / 180.0)))

## Sample `fn(phase) -> Vector3` (metres, offset from rest) onto a position track.
func pos(a: Animation, bone: String, fn: Callable) -> void:
	var ti := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(ti, NodePath("%s:%s" % [SKEL, bone]))
	a.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
	var base: Vector3 = rest[bone]
	var n := maxi(2, int(round(a.length * KEY_FPS)))
	for i in n + 1:
		var p := float(i) / float(n)
		a.position_track_insert_key(ti, p * a.length, base + (fn.call(p) as Vector3))

## Apply the same curve to both sides, with an optional phase shift and a
## mirror on the Y/Z components so limbs swing symmetrically.
func rot_lr(a: Animation, stem: String, fn: Callable, phase_r: float = 0.5, mirror: bool = true) -> void:
	rot(a, stem + ".L", func(p): return fn.call(p))
	rot(a, stem + ".R", func(p):
		var e: Vector3 = fn.call(fposmod(p + phase_r, 1.0))
		return Vector3(e.x, -e.y, -e.z) if mirror else e)

func _s(p: float, cycles: float = 1.0, phase: float = 0.0) -> float:
	return sin((p * cycles + phase) * TAU)

## Smooth 0->1->0 pulse centred on `at`, `width` wide. Used for twitches,
## snaps and impacts that should not read as a sine.
func _pulse(p: float, at: float, width: float) -> float:
	var d := (p - at) / width
	return exp(-d * d * 4.0)

## Eased ramp from 0 to 1 between t0 and t1.
func _ramp(p: float, t0: float, t1: float) -> float:
	if p <= t0:
		return 0.0
	if p >= t1:
		return 1.0
	var x := (p - t0) / (t1 - t0)
	return x * x * (3.0 - 2.0 * x)

# ----------------------------------------------------------- limb machinery

## One stride of a digitigrade hind leg. `p` is stride phase, 0 = mid-stance.
func _leg(p: float, amp: float, lift: float) -> Dictionary:
	var swing := -amp * cos(p * TAU)                 # + swings the leg forward
	var flex := maxf(0.0, sin(p * TAU)) * lift       # folds up during the swing
	return {
		"thigh": Vector3(swing, 0.0, 0.0),
		"shin": Vector3(-flex * 1.25 - amp * 0.20, 0.0, 0.0),
		"hock": Vector3(flex * 1.05 + amp * 0.18, 0.0, 0.0),
		"foot": Vector3(-flex * 0.45 + amp * 0.10, 0.0, 0.0),
	}

## One stride of an arm being used as a front leg.
func _arm(p: float, amp: float, lift: float) -> Dictionary:
	var swing := -amp * cos(p * TAU)
	var flex := maxf(0.0, sin(p * TAU)) * lift
	return {
		"upper": Vector3(swing, 0.0, 0.0),
		"fore1": Vector3(-flex * 0.75, 0.0, 0.0),
		"fore2": Vector3(-flex * 0.35, 0.0, 0.0),
		"hand": Vector3(flex * 0.55, 0.0, 0.0),
	}

func add_leg(a: Animation, side: String, phase: float, amp: float, lift: float) -> void:
	var pick := func(key: String) -> Callable:
		return func(p): return _leg(fposmod(p + phase, 1.0), amp, lift)[key]
	rot(a, "Thigh." + side, pick.call("thigh"))
	rot(a, "Shin." + side, pick.call("shin"))
	rot(a, "Hock." + side, pick.call("hock"))
	rot(a, "Foot." + side, pick.call("foot"))

func add_arm(a: Animation, side: String, phase: float, amp: float, lift: float) -> void:
	var pick := func(key: String) -> Callable:
		return func(p): return _arm(fposmod(p + phase, 1.0), amp, lift)[key]
	rot(a, "UpperArm." + side, pick.call("upper"))
	rot(a, "Forearm1." + side, pick.call("fore1"))
	rot(a, "Forearm2." + side, pick.call("fore2"))
	rot(a, "Hand." + side, pick.call("hand"))

## Light trailing sway on the antler chains, driven by head motion.
func add_antler_sway(a: Animation, amp: float, cycles: float, phase: float = 0.0) -> void:
	for side in ["L", "R"]:
		var sgn := 1.0 if side == "L" else -1.0
		for i in [2, 3]:
			var lag := phase - 0.06 * float(i)
			var scale := amp * (0.6 if i == 2 else 1.0)
			rot(a, "Antler.%s%d" % [side, i], func(p): return Vector3(
				_s(p, cycles, lag) * scale * 0.6,
				_s(p, cycles, lag + 0.15) * scale * sgn,
				_s(p, cycles, lag) * scale * 0.4 * sgn))

# ----------------------------------------------------------------- the clips

## 1. Idle -- labored breathing, the ribcage visibly working, occasional head
## twitch, weight rocking between the long arms and the hind legs.
func clip_idle() -> Animation:
	var a := _anim(4.0, true)
	# Breath is 2 cycles over the clip, with a sharp intake and slow release.
	var breath := func(p): return pow(maxf(0.0, sin(p * 2.0 * TAU)), 0.6)
	pos(a, "Hips", func(p): return Vector3(0, -0.014 * breath.call(p) + 0.008 * _s(p, 1.0), 0))
	rot(a, "Hips", func(p): return Vector3(1.2 * breath.call(p), 0, 2.0 * _s(p, 1.0)))
	for i in [2, 3, 4]:
		rot(a, "Spine%d" % i, func(p): return Vector3(
			-2.4 * breath.call(p), 0.6 * _s(p, 1.0, 0.2), 1.1 * _s(p, 1.0, 0.3)))
	# Two quick, wrong-looking head twitches per loop.
	var twitch := func(p): return _pulse(p, 0.34, 0.035) - 0.7 * _pulse(p, 0.71, 0.028)
	rot(a, "Neck1", func(p): return Vector3(2.0 * breath.call(p) - 1.5, 3.0 * _s(p, 1.0, 0.1), 0))
	rot(a, "Neck2", func(p): return Vector3(2.5 * _s(p, 1.0, 0.25), 5.0 * _s(p, 1.0, 0.35), 0))
	rot(a, "Head", func(p): return Vector3(
		1.8 * _s(p, 2.0, 0.4) - 2.0 * twitch.call(p),
		16.0 * twitch.call(p) + 2.5 * _s(p, 1.0, 0.5),
		4.0 * twitch.call(p)))
	# Jaw hangs open and works with the breath.
	rot(a, "Jaw", func(p): return Vector3(7.0 + 4.0 * breath.call(p), 0, 0))
	add_arm(a, "L", 0.0, 3.0, 2.0)
	add_arm(a, "R", 0.5, 2.4, 1.6)
	add_leg(a, "L", 0.25, 2.0, 1.2)
	add_leg(a, "R", 0.75, 2.0, 1.2)
	add_antler_sway(a, 2.2, 1.0)
	return a

## 2. Walk -- semi-quadrupedal lope. Limb phases are deliberately NOT evenly
## spaced, so the rhythm limps instead of resolving into a clean gait.
func clip_walk() -> Animation:
	var a := _anim(1.6, true)
	pos(a, "Hips", func(p): return Vector3(
		0.02 * _s(p, 1.0, 0.1), -0.05 + 0.035 * absf(sin(p * 2.0 * TAU)), 0))
	rot(a, "Hips", func(p): return Vector3(6.0, 3.5 * _s(p, 1.0), 7.0 * _s(p, 1.0, 0.12)))
	for i in [2, 3, 4]:
		rot(a, "Spine%d" % i, func(p): return Vector3(
			-3.0 + 2.2 * _s(p, 2.0), 2.0 * _s(p, 1.0, 0.2), -2.5 * _s(p, 1.0, 0.15)))
	rot(a, "Neck1", func(p): return Vector3(6.0 + 4.0 * _s(p, 2.0, 0.3), 4.0 * _s(p, 1.0, 0.4), 0))
	rot(a, "Neck2", func(p): return Vector3(-4.0 + 3.0 * _s(p, 2.0, 0.45), 5.0 * _s(p, 1.0, 0.5), 0))
	rot(a, "Head", func(p): return Vector3(
		3.0 * _s(p, 2.0, 0.5), 6.0 * _s(p, 1.0, 0.55), 3.0 * _s(p, 1.0, 0.3)))
	rot(a, "Jaw", func(p): return Vector3(6.0 + 3.0 * _s(p, 2.0, 0.2), 0, 0))
	# Off-beat phases: 0.00 / 0.42 for the arms, 0.55 / 0.05 for the legs.
	add_arm(a, "L", 0.00, 26.0, 30.0)
	add_arm(a, "R", 0.42, 24.0, 27.0)
	add_leg(a, "L", 0.55, 22.0, 26.0)
	add_leg(a, "R", 0.05, 21.0, 24.0)
	add_antler_sway(a, 4.0, 1.0, 0.1)
	return a

## 3. Run -- full quadrupedal sprint, arms driving as front legs, body pitching
## through a bound rather than a trot.
func clip_run() -> Animation:
	var a := _anim(0.9, true)
	pos(a, "Hips", func(p): return Vector3(0, -0.14 + 0.10 * absf(sin(p * TAU)), 0.03 * _s(p, 1.0)))
	rot(a, "Hips", func(p): return Vector3(16.0 + 9.0 * _s(p, 1.0, 0.1), 2.0 * _s(p, 1.0), 4.0 * _s(p, 1.0, 0.2)))
	for i in [2, 3, 4]:
		rot(a, "Spine%d" % i, func(p): return Vector3(-7.0 + 6.5 * _s(p, 1.0, 0.15), 0, 0))
	rot(a, "Neck1", func(p): return Vector3(14.0 + 5.0 * _s(p, 1.0, 0.3), 0, 0))
	rot(a, "Neck2", func(p): return Vector3(-10.0 + 4.0 * _s(p, 1.0, 0.4), 0, 0))
	rot(a, "Head", func(p): return Vector3(-6.0 + 4.0 * _s(p, 1.0, 0.5), 3.0 * _s(p, 1.0, 0.5), 0))
	rot(a, "Jaw", func(p): return Vector3(12.0 + 6.0 * _s(p, 1.0, 0.2), 0, 0))
	# Bound: the two arms land almost together, then the two legs.
	add_arm(a, "L", 0.00, 44.0, 52.0)
	add_arm(a, "R", 0.10, 42.0, 50.0)
	add_leg(a, "L", 0.52, 38.0, 46.0)
	add_leg(a, "R", 0.60, 37.0, 44.0)
	add_antler_sway(a, 6.0, 1.0, 0.12)
	return a

## 4. Alert -- the head snaps to a target and the antlers lead the motion,
## everything else locking rigid behind it.
func clip_alert() -> Animation:
	var a := _anim(1.1, false)
	var snap := func(p): return _ramp(p, 0.06, 0.20) - 0.18 * _pulse(p, 0.30, 0.07)
	rot(a, "Hips", func(p): return Vector3(0, 5.0 * snap.call(p), 0))
	for i in [3, 4]:
		rot(a, "Spine%d" % i, func(p): return Vector3(-1.5, 8.0 * snap.call(p), 0))
	rot(a, "Neck1", func(p): return Vector3(-3.0 * snap.call(p), 18.0 * snap.call(p), 0))
	rot(a, "Neck2", func(p): return Vector3(-6.0 * snap.call(p), 22.0 * snap.call(p), 0))
	rot(a, "Head", func(p): return Vector3(
		-4.0 * snap.call(p), 30.0 * snap.call(p), 6.0 * snap.call(p)))
	rot(a, "Jaw", func(p): return Vector3(4.0 + 10.0 * _pulse(p, 0.26, 0.06), 0, 0))
	add_antler_sway(a, 7.0, 1.0, 0.35)
	return a

## 5. Attack (claw) -- one-arm wide slash. Coils back and out, then sweeps
## across the body; the spine whips through a beat behind the arm.
func clip_attack_claw() -> Animation:
	var a := _anim(1.1, false)
	var wind := func(p): return _ramp(p, 0.0, 0.26) - _ramp(p, 0.28, 0.44)
	var strike := func(p): return _ramp(p, 0.28, 0.44) - _ramp(p, 0.58, 0.95)
	rot(a, "Hips", func(p): return Vector3(
		4.0 * wind.call(p) + 8.0 * strike.call(p),
		-14.0 * wind.call(p) + 20.0 * strike.call(p), 0))
	for i in [3, 4, 5]:
		rot(a, "Spine%d" % i, func(p): return Vector3(
			-4.0 * wind.call(p) + 6.0 * strike.call(p),
			-12.0 * wind.call(p) + 18.0 * strike.call(p),
			-5.0 * wind.call(p) + 8.0 * strike.call(p)))
	rot(a, "Neck1", func(p): return Vector3(
		-6.0 * wind.call(p) + 8.0 * strike.call(p), -8.0 * wind.call(p) + 10.0 * strike.call(p), 0))
	rot(a, "Head", func(p): return Vector3(
		-4.0 * wind.call(p) + 6.0 * strike.call(p), -10.0 * wind.call(p) + 14.0 * strike.call(p), 0))
	rot(a, "Jaw", func(p): return Vector3(6.0 + 16.0 * strike.call(p), 0, 0))
	# Striking arm: back and out on the wind, forward and across on the strike.
	rot(a, "UpperArm.R", func(p): return Vector3(
		-30.0 * wind.call(p) + 42.0 * strike.call(p), 0,
		-48.0 * wind.call(p) + 58.0 * strike.call(p)))
	rot(a, "Forearm1.R", func(p): return Vector3(
		-40.0 * wind.call(p) - 18.0 * strike.call(p), 0, -12.0 * strike.call(p)))
	rot(a, "Forearm2.R", func(p): return Vector3(-18.0 * wind.call(p) - 8.0 * strike.call(p), 0, 0))
	rot(a, "Hand.R", func(p): return Vector3(-14.0 * wind.call(p) + 22.0 * strike.call(p), 0, 0))
	for f in 5:
		rot(a, "Finger%d_1.R" % f, func(p): return Vector3(
			-26.0 * wind.call(p) - 34.0 * strike.call(p), 0, 0))
	# Planted arm takes the weight and braces.
	rot(a, "UpperArm.L", func(p): return Vector3(
		-10.0 * wind.call(p) - 16.0 * strike.call(p), 0, 6.0 * strike.call(p)))
	rot(a, "Forearm1.L", func(p): return Vector3(10.0 * wind.call(p) + 14.0 * strike.call(p), 0, 0))
	add_leg(a, "L", 0.0, 5.0, 4.0)
	add_leg(a, "R", 0.5, 5.0, 4.0)
	add_antler_sway(a, 5.0, 1.0, 0.3)
	return a

## 6. Attack (bite) -- the neck coils, thrusts the skull forward, and the jaw
## snaps shut a couple of frames past full extension.
func clip_attack_bite() -> Animation:
	var a := _anim(1.0, false)
	var coil := func(p): return _ramp(p, 0.0, 0.22) - _ramp(p, 0.24, 0.40)
	var lunge := func(p): return _ramp(p, 0.24, 0.40) - _ramp(p, 0.56, 0.92)
	pos(a, "Hips", func(p): return Vector3(
		0, 0.02 * coil.call(p), 0.10 * coil.call(p) - 0.18 * lunge.call(p)))
	rot(a, "Hips", func(p): return Vector3(8.0 * coil.call(p) - 12.0 * lunge.call(p), 0, 0))
	for i in [3, 4, 5]:
		rot(a, "Spine%d" % i, func(p): return Vector3(
			6.0 * coil.call(p) - 9.0 * lunge.call(p), 0, 0))
	rot(a, "Neck1", func(p): return Vector3(24.0 * coil.call(p) - 32.0 * lunge.call(p), 0, 0))
	rot(a, "Neck2", func(p): return Vector3(20.0 * coil.call(p) - 28.0 * lunge.call(p), 0, 0))
	rot(a, "Head", func(p): return Vector3(16.0 * coil.call(p) - 22.0 * lunge.call(p), 0, 0))
	# Gape wide through the lunge, then snap shut just past full extension.
	rot(a, "Jaw", func(p): return Vector3(
		6.0 + 34.0 * coil.call(p) + 30.0 * lunge.call(p) - 62.0 * _ramp(p, 0.44, 0.52), 0, 0))
	rot_lr(a, "UpperArm", func(p): return Vector3(-18.0 * lunge.call(p), 0, 0), 0.0, false)
	rot_lr(a, "Forearm1", func(p): return Vector3(14.0 * lunge.call(p), 0, 0), 0.0, false)
	add_leg(a, "L", 0.0, 6.0, 5.0)
	add_leg(a, "R", 0.5, 6.0, 5.0)
	add_antler_sway(a, 6.0, 1.0, 0.28)
	return a

## 7. Roar -- ribcage hauls open, head goes back, jaw to full gape and holds.
func clip_roar() -> Animation:
	var a := _anim(1.8, false)
	var rear := func(p): return _ramp(p, 0.05, 0.28) - _ramp(p, 0.74, 1.0)
	var shake := func(p): return sin(p * 26.0 * TAU) * _ramp(p, 0.26, 0.34) * (1.0 - _ramp(p, 0.68, 0.80))
	pos(a, "Hips", func(p): return Vector3(0, 0.05 * rear.call(p), 0.06 * rear.call(p)))
	rot(a, "Hips", func(p): return Vector3(10.0 * rear.call(p), 0, 0))
	for i in [2, 3, 4, 5]:
		rot(a, "Spine%d" % i, func(p): return Vector3(
			8.0 * rear.call(p) + 1.5 * shake.call(p), 0, 0))
	rot(a, "Neck1", func(p): return Vector3(26.0 * rear.call(p) + 2.0 * shake.call(p), 0, 0))
	rot(a, "Neck2", func(p): return Vector3(30.0 * rear.call(p) + 2.5 * shake.call(p), 0, 0))
	rot(a, "Head", func(p): return Vector3(34.0 * rear.call(p) + 3.0 * shake.call(p), 0, 0))
	rot(a, "Jaw", func(p): return Vector3(6.0 + 52.0 * rear.call(p) + 4.0 * shake.call(p), 0, 0))
	rot_lr(a, "UpperArm", func(p): return Vector3(-14.0 * rear.call(p), 0, -10.0 * rear.call(p)), 0.0)
	rot_lr(a, "Forearm1", func(p): return Vector3(-20.0 * rear.call(p), 0, 0), 0.0, false)
	add_leg(a, "L", 0.0, 7.0, 5.0)
	add_leg(a, "R", 0.5, 7.0, 5.0)
	add_antler_sway(a, 9.0, 1.5, 0.2)
	return a

## 8. Hit reaction -- hard flinch folding around the wounded left flank, then
## a stagger back onto the hind legs.
func clip_hit() -> Animation:
	var a := _anim(0.65, false)
	var hit := func(p): return _pulse(p, 0.14, 0.10) + 0.45 * _pulse(p, 0.34, 0.16)
	var settle := func(p): return 1.0 - _ramp(p, 0.30, 1.0)
	pos(a, "Hips", func(p): return Vector3(
		-0.06 * hit.call(p), -0.09 * hit.call(p), 0.13 * hit.call(p)))
	rot(a, "Hips", func(p): return Vector3(
		14.0 * hit.call(p), -10.0 * hit.call(p), 12.0 * hit.call(p)))
	for i in [2, 3, 4, 5]:
		rot(a, "Spine%d" % i, func(p): return Vector3(
			11.0 * hit.call(p), -7.0 * hit.call(p), 9.0 * hit.call(p) * settle.call(p)))
	rot(a, "Neck1", func(p): return Vector3(16.0 * hit.call(p), -12.0 * hit.call(p), 0))
	rot(a, "Neck2", func(p): return Vector3(12.0 * hit.call(p), -10.0 * hit.call(p), 0))
	rot(a, "Head", func(p): return Vector3(
		14.0 * hit.call(p), -16.0 * hit.call(p), 8.0 * hit.call(p)))
	rot(a, "Jaw", func(p): return Vector3(6.0 + 30.0 * hit.call(p), 0, 0))
	rot_lr(a, "UpperArm", func(p): return Vector3(-24.0 * hit.call(p), 0, -14.0 * hit.call(p)), 0.12)
	rot_lr(a, "Forearm1", func(p): return Vector3(26.0 * hit.call(p), 0, 0), 0.12, false)
	rot_lr(a, "Thigh", func(p): return Vector3(-12.0 * hit.call(p), 0, 0), 0.2, false)
	rot_lr(a, "Shin", func(p): return Vector3(14.0 * hit.call(p), 0, 0), 0.2, false)
	add_antler_sway(a, 10.0, 1.2, 0.1)
	return a

## 9. Death -- hind legs give out first, the body sinks forward onto the chest,
## and the long arms fold up underneath it last.
func clip_death() -> Animation:
	var a := _anim(2.4, false)
	var buckle := func(p): return _ramp(p, 0.10, 0.34)   # hind legs go
	var sink := func(p): return _ramp(p, 0.28, 0.62)     # chest comes down
	var fold := func(p): return _ramp(p, 0.52, 0.88)     # arms crumple last
	var twitch := func(p): return _pulse(p, 0.80, 0.03) * 0.5
	pos(a, "Hips", func(p): return Vector3(
		0.05 * sink.call(p),
		-0.58 * buckle.call(p) - 0.46 * sink.call(p),
		0.08 * buckle.call(p) - 0.04 * sink.call(p)))
	rot(a, "Hips", func(p): return Vector3(
		-8.0 * buckle.call(p) + 16.0 * sink.call(p), 6.0 * sink.call(p),
		10.0 * buckle.call(p) + 26.0 * sink.call(p)))
	for i in [2, 3, 4, 5]:
		rot(a, "Spine%d" % i, func(p): return Vector3(
			4.0 * buckle.call(p) + 7.0 * sink.call(p), 2.0 * sink.call(p), 4.0 * sink.call(p)))
	rot(a, "Neck1", func(p): return Vector3(
		7.0 * buckle.call(p) - 26.0 * sink.call(p) + 4.0 * twitch.call(p), 5.0 * sink.call(p), 0))
	rot(a, "Neck2", func(p): return Vector3(
		5.0 * buckle.call(p) - 24.0 * sink.call(p), 6.0 * sink.call(p), 0))
	rot(a, "Head", func(p): return Vector3(
		9.0 * buckle.call(p) - 30.0 * sink.call(p) + 6.0 * twitch.call(p),
		8.0 * sink.call(p), 10.0 * sink.call(p)))
	rot(a, "Jaw", func(p): return Vector3(8.0 + 26.0 * buckle.call(p) - 10.0 * fold.call(p), 0, 0))
	# Hind legs collapse under the body.
	rot_lr(a, "Thigh", func(p): return Vector3(48.0 * buckle.call(p), 0, 0), 0.06, false)
	rot_lr(a, "Shin", func(p): return Vector3(-62.0 * buckle.call(p), 0, 0), 0.06, false)
	rot_lr(a, "Hock", func(p): return Vector3(54.0 * buckle.call(p), 0, 0), 0.06, false)
	rot_lr(a, "Foot", func(p): return Vector3(-24.0 * buckle.call(p), 0, 0), 0.06, false)
	# Arms hold the weight, then give.
	rot_lr(a, "UpperArm", func(p): return Vector3(
		16.0 * sink.call(p) - 34.0 * fold.call(p), 0, -26.0 * fold.call(p)), 0.1)
	rot_lr(a, "Forearm1", func(p): return Vector3(
		6.0 * buckle.call(p) - 62.0 * fold.call(p), 0, 0), 0.1, false)
	rot_lr(a, "Forearm2", func(p): return Vector3(-34.0 * fold.call(p), 0, 0), 0.1, false)
	rot_lr(a, "Hand", func(p): return Vector3(28.0 * fold.call(p), 0, 0), 0.1, false)
	add_antler_sway(a, 8.0, 0.8, 0.15)
	return a

# ------------------------------------------------------------------ library

func build_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", clip_idle())
	lib.add_animation("walk", clip_walk())
	lib.add_animation("run", clip_run())
	lib.add_animation("alert", clip_alert())
	lib.add_animation("attack_claw", clip_attack_claw())
	lib.add_animation("attack_bite", clip_attack_bite())
	lib.add_animation("roar", clip_roar())
	lib.add_animation("hit", clip_hit())
	lib.add_animation("death", clip_death())
	return lib
