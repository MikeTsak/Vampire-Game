extends SceneTree
## Runtime audit of the player's shadow body.
##
## Checks it is wired into the Player, renders shadows-only, stands where the
## player stands, and that the driver picks the clip that matches what the
## player is doing.
##
## Run headless:
##   godot --headless --path <project> --script res://tools/verify_player_shadow_new.gd

const CLIPS := ["idle", "walk", "run", "aim"]

var failures: Array[String] = []
var player: Node
var frame := 0

func _initialize() -> void:
	player = (load("res://scenes/characters/Player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	current_scene = player

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append(msg)
	return cond

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false

	var shadow := player.get_node_or_null("ShadowCaster")
	if not _check(shadow != null, "Player has no ShadowCaster"):
		return _finish()
	_check(shadow.scene_file_path == "res://scenes/characters/player_shadow_new.tscn",
		"ShadowCaster is %s, not the generated shadow body" % shadow.scene_file_path)

	var sk := shadow.get_node_or_null("Skeleton3D") as Skeleton3D
	var ap := shadow.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not _check(sk != null and ap != null, "shadow body is missing its rig"):
		return _finish()

	# ── shadows only, never drawn ──────────────────────────────────────────
	var mi: MeshInstance3D = null
	for c in sk.get_children():
		if c is MeshInstance3D:
			mi = c
	if not _check(mi != null, "no MeshInstance3D under the shadow skeleton"):
		return _finish()
	_check(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"shadow body cast_shadow is %d, expected shadows-only (3)" % mi.cast_shadow)
	_check(mi.skin != null, "shadow body has no skin")
	_check(mi.skeleton == NodePath(".."), "shadow mesh is not bound to its skeleton")

	# ── the body is a body ─────────────────────────────────────────────────
	var mesh := mi.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	_check(bones != null and bones.size() == verts.size() * 4,
		"shadow mesh is not skinned four-per-vertex")
	var aabb := mesh.get_aabb()
	_check(absf(aabb.position.y) < 0.02,
		"shadow body does not stand on the ground (feet at %.3f)" % aabb.position.y)
	_check(aabb.size.y > 1.65 and aabb.size.y < 1.95,
		"shadow body is %.2f m tall" % aabb.size.y)
	# the rifle sticks out well past the chest, which is what makes the
	# silhouette read as armed rather than as a post
	_check(aabb.size.z > 0.85,
		"nothing projects forward far enough to read as a carried rifle (%.2f m)"
			% aabb.size.z)
	for name in ["head", "hand_r", "hand_l", "weapon", "foot_l", "foot_r"]:
		_check(sk.find_bone(name) >= 0, "rig has no '%s' bone" % name)

	# ── clips ──────────────────────────────────────────────────────────────
	var got := ap.get_animation_list()
	got.sort()
	var want := CLIPS.duplicate()
	want.sort()
	_check(Array(got) == want, "clips are %s, expected %s" % [str(got), str(want)])
	for clip in CLIPS:
		if not ap.has_animation(clip):
			continue
		var anim := ap.get_animation(clip)
		_check(anim.loop_mode != Animation.LOOP_NONE, "'%s' does not loop" % clip)
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			_check(sk.find_bone(String(path.get_concatenated_subnames())) >= 0,
				"'%s' track %d targets %s, not a bone" % [clip, t, str(path)])
		var moved := _moved(sk, ap, clip, anim.length)
		_check(moved >= 6,
			"'%s' shifts only %d bones off the rest pose" % [clip, moved])

	# ── the driver picks the right clip for the player's state ─────────────
	for probe in [{"speed": 0.0, "ads": 0.0, "want": "idle"},
			{"speed": 4.4, "ads": 0.0, "want": "walk"},
			{"speed": 8.4, "ads": 0.0, "want": "run"},
			{"speed": 0.0, "ads": 1.0, "want": "aim"},
			{"speed": 4.4, "ads": 1.0, "want": "aim"}]:
		player.velocity = Vector3(probe["speed"], 0.0, 0.0)
		player.set("_ads_blend", probe["ads"])
		shadow._process(0.016)
		_check(ap.current_animation == probe["want"],
			"at %.1f m/s ads=%.0f the shadow plays '%s', expected '%s'"
				% [probe["speed"], probe["ads"], ap.current_animation, probe["want"]])

	print("player shadow: %d bones, %d tris, %.2f m tall, %.2f m of rifle reach"
		% [sk.get_bone_count(), mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3,
			aabb.size.y, aabb.size.z])
	return _finish()

## How many bones the clip actually shifts off the rest pose at some point.
## Measured against rest rather than against the clip's own first frame: aim is
## a held pose and barely moves internally, but it must still put the body
## somewhere quite different from standing.
func _moved(sk: Skeleton3D, ap: AnimationPlayer, clip: String, length: float) -> int:
	ap.stop()
	sk.reset_bone_poses()
	var base: Array[Vector3] = []
	for i in sk.get_bone_count():
		base.append(sk.get_bone_global_pose(i).origin)
	ap.play(clip)
	var seen := {}
	for s in range(0, 13):
		ap.seek(length * float(s) / 12.0, true)
		ap.advance(0.0)
		for i in sk.get_bone_count():
			if sk.get_bone_global_pose(i).origin.distance_to(base[i]) > 0.004:
				seen[i] = true
	ap.stop()
	sk.reset_bone_poses()
	return seen.size()

func _finish() -> bool:
	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		print("FAIL (%d):" % failures.size())
		for m in failures:
			print("  - ", m)
		quit(1)
	return true
