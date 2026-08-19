extends SceneTree
## Runtime audit of the generated animal scenes.
##
## Loads each scene for real, then drives every clip and re-skins a sample of
## vertices by hand -- bone global pose times the skin's bind pose -- so the
## report reflects where the mesh actually ends up, not merely that some
## animation tracks exist.
##
## Run headless:
##   godot --headless --path <project> --script res://tools/verify_scenes_new.gd

const MANIFEST := "res://models/animals/animals_new.json"
const REQUIRED := ["idle", "walk", "death"]
const LOOPING := ["idle", "walk"]

var failures: Array[String] = []
var entries: Array = []
var live: Array[Node] = []

## Scenes are instantiated here but inspected a frame later: _ready -- and the
## group registration inside it -- has not run yet at initialize time.
func _initialize() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	entries = JSON.parse_string(f.get_as_text())
	f.close()

	for e in entries:
		var packed := load(e["scene"]) as PackedScene
		if packed == null:
			failures.append("%s: scene will not load" % e["name"])
			live.append(null)
			continue
		var inst := packed.instantiate()
		root.add_child(inst)
		# the wander AI would fight our own seeking
		inst.set_physics_process(false)
		live.append(inst)

func _process(_delta: float) -> bool:
	print("verifying %d animal scenes" % entries.size())
	for i in entries.size():
		if live[i] != null:
			_verify(entries[i], live[i])

	for inst in live:
		if inst != null:
			inst.free()

	if failures.is_empty():
		print("")
		print("all %d scenes pass runtime verification" % entries.size())
		quit(0)
	else:
		print("")
		print("FAILED (%d):" % failures.size())
		for m in failures:
			print("  - ", m)
		quit(1)
	return true

func _check(cond: bool, model: String, msg: String) -> bool:
	if not cond:
		failures.append("%s: %s" % [model, msg])
	return cond

func _verify(e: Dictionary, inst: Node) -> void:
	var name: String = e["name"]
	_check(inst is CharacterBody3D, name, "root is %s, not CharacterBody3D" % inst.get_class())
	_check(inst.get_script() != null, name, "root carries no script")
	_check(inst.is_in_group("animals"), name, "root never joined the animals group")

	var sk := inst.get_node_or_null("MeshBase/Skeleton3D") as Skeleton3D
	var ap := inst.get_node_or_null("MeshBase/AnimationPlayer") as AnimationPlayer
	var col := inst.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not _check(sk != null and ap != null and col != null, name,
			"expected MeshBase/Skeleton3D, MeshBase/AnimationPlayer and CollisionShape3D"):
		return

	_check(sk.get_bone_count() == int(e["bones"]), name,
		"skeleton has %d bones, manifest says %d" % [sk.get_bone_count(), e["bones"]])
	_check(col.shape is BoxShape3D, name, "collision shape is not a box")

	# -- mesh, skin, material -------------------------------------------------
	var mi: MeshInstance3D = null
	for c in sk.get_children():
		if c is MeshInstance3D:
			mi = c
	if not _check(mi != null, name, "no MeshInstance3D under the skeleton"):
		return
	_check(mi.skin != null, name, "MeshInstance3D has no skin")
	_check(mi.skeleton == NodePath(".."), name,
		"MeshInstance3D skeleton path is %s" % str(mi.skeleton))

	var mesh := mi.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	_check(uvs != null and uvs.size() == verts.size(), name, "mesh lost its UVs")
	_check(bones != null and bones.size() == verts.size() * 4, name,
		"mesh does not carry four bone indices per vertex")
	_check(weights != null and weights.size() == verts.size() * 4, name,
		"mesh does not carry four weights per vertex")
	var mat := mesh.surface_get_material(0) as StandardMaterial3D
	if _check(mat != null, name, "surface has no StandardMaterial3D"):
		_check(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, name,
			"texture_filter is %d, expected 0 (nearest)" % mat.texture_filter)
		var tex := mat.albedo_texture
		if _check(tex != null, name, "material has no albedo texture"):
			_check(tex.get_width() == 128 and tex.get_height() == 128, name,
				"atlas is %dx%d, expected 128x128" % [tex.get_width(), tex.get_height()])
			_check(tex.resource_path == e["atlas"], name,
				"material points at %s, not the generated atlas" % tex.resource_path)

	# -- animations -----------------------------------------------------------
	var clips := ap.get_animation_list()
	clips.sort()
	var want := REQUIRED.duplicate()
	want.sort()
	_check(Array(clips) == want, name,
		"clips are %s, expected exactly %s" % [str(clips), str(want)])
	for clip in REQUIRED:
		if not ap.has_animation(clip):
			continue
		var anim := ap.get_animation(clip)
		var wants_loop: bool = clip in LOOPING
		var loops := anim.loop_mode != Animation.LOOP_NONE
		_check(loops == wants_loop, name,
			"'%s' loop_mode is %d" % [clip, anim.loop_mode])
		_check(anim.get_track_count() >= 14, name,
			"'%s' drives only %d tracks" % [clip, anim.get_track_count()])
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			_check(sk.find_bone(String(path.get_concatenated_subnames())) >= 0, name,
				"'%s' track %d targets %s, which is not a bone" % [clip, t, str(path)])

	# -- does the rig actually move the skin? ---------------------------------
	# _ready() starts idle at a random offset to desync a herd, so the bind
	# pose has to be restored before the mesh can be measured against it
	ap.stop()
	sk.reset_bone_poses()
	var rest := _skinned_aabb(sk, mi, verts, bones, weights)
	_check(absf(rest.position.y - float(e["mesh_floor"])) < 0.04, name,
		"rest pose does not stand on the ground (min y %.3f)" % rest.position.y)
	# antlers and tusks are outside the collider by design, so the bind-pose
	# bounds are checked against the authored mesh bounds, not the box
	_check(absf(rest.size.y - float(e["mesh_height"])) < 0.04, name,
		"rest height %.2f, authored %.2f" % [rest.size.y, e["mesh_height"]])
	_check(absf(rest.size.z - float(e["mesh_length"])) < 0.04, name,
		"rest length %.2f, authored %.2f" % [rest.size.z, e["mesh_length"]])
	_check(float(e["collider_size"][1]) <= float(e["mesh_height"]) + 0.01, name,
		"collider is taller than the model")

	var report := {}
	for clip in REQUIRED:
		if not ap.has_animation(clip):
			continue
		var anim := ap.get_animation(clip)
		var moved := _pose_spread(sk, ap, clip, anim.length)
		_check(moved["bones"] >= 8, name,
			"'%s' visibly moves only %d bones" % [clip, moved["bones"]])
		_check(moved["max"] > 0.02, name,
			"'%s' moves its bones by at most %.4f m" % [clip, moved["max"]])
		report[clip] = moved

	# Death has to put the animal on its side. Bounding height is a poor test
	# for that -- a boar lying down is nearly as tall as it stands -- so the
	# chest bone is measured instead: it has to end up near the ground.
	var chest := sk.find_bone("chest")
	# the clip sweep above left the skeleton wherever death ended
	ap.stop()
	sk.reset_bone_poses()
	var chest_up: float = sk.get_bone_global_pose(chest).origin.y
	_check(chest_up > 0.0, name, "chest bone sits below the origin at rest")
	ap.play("death")
	ap.seek(ap.get_animation("death").length, true)
	ap.advance(0.0)
	var chest_down: float = sk.get_bone_global_pose(chest).origin.y
	var down := _skinned_aabb(sk, mi, verts, bones, weights)
	# A stocky animal on its side still carries its chest half a body-width
	# off the floor, and a sheep crumples legs-first rather than toppling
	# wide, so neither the drop nor the bounds settle it on their own. The
	# unambiguous test is the root bone: its up axis has to end up on its side.
	_check(chest_down < chest_up * 0.75, name,
		"death leaves the chest at %.2f m, standing height was %.2f m"
			% [chest_down, chest_up])
	var tipped := rad_to_deg(sk.get_bone_global_pose(sk.find_bone("root")).basis.y.angle_to(Vector3.UP))
	_check(tipped > 60.0, name,
		"the body only tips %.0f degrees off vertical" % tipped)
	_check(down.size.y < rest.size.y * 0.92, name,
		"the body is no shorter after death (%.2f against %.2f)"
			% [down.size.y, rest.size.y])
	# and it has to come to rest ON the ground -- neither hovering above it
	# nor buried in it
	_check(down.position.y < 0.10, name,
		"the collapsed body floats %.2f m off the ground" % down.position.y)
	_check(down.position.y > -0.10, name,
		"the collapsed body sinks %.2f m into the ground" % down.position.y)

	print("  %-16s stands %.2fm  chest %.2f->%.2fm, rolls %.0f deg  bones moved idle/walk/death %d/%d/%d  peak swing %.2fm"
		% [name, rest.size.y, chest_up, chest_down, tipped,
			report["idle"]["bones"], report["walk"]["bones"], report["death"]["bones"],
			report["walk"]["max"]])


## Skins a sample of vertices by hand and returns the bounding box they occupy
## in the current pose: bone_global_pose * skin_bind_pose, weighted.
func _skinned_aabb(sk: Skeleton3D, mi: MeshInstance3D, verts: PackedVector3Array,
		bones, weights) -> AABB:
	var skin := mi.skin
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = sk.find_bone(skin.get_bind_name(i))
		mats.append(sk.get_bone_global_pose(b) * skin.get_bind_pose(i))

	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in verts.size():
		var p := Vector3.ZERO
		for k in 4:
			var w: float = weights[v * 4 + k]
			if w > 0.0:
				p += (mats[bones[v * 4 + k]] * verts[v]) * w
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)

## Plays a clip across its length and measures how far each bone travels from
## where it sits at time zero.
func _pose_spread(sk: Skeleton3D, ap: AnimationPlayer, clip: String,
		length: float) -> Dictionary:
	ap.play(clip)
	ap.seek(0.0, true)
	ap.advance(0.0)
	var base: Array[Vector3] = []
	for i in sk.get_bone_count():
		base.append(sk.get_bone_global_pose(i).origin)

	var moved := 0
	var peak := 0.0
	var per_bone := PackedFloat32Array()
	per_bone.resize(sk.get_bone_count())
	for s in range(1, 13):
		ap.seek(length * float(s) / 12.0, true)
		ap.advance(0.0)
		for i in sk.get_bone_count():
			var d: float = sk.get_bone_global_pose(i).origin.distance_to(base[i])
			per_bone[i] = maxf(per_bone[i], d)
			peak = maxf(peak, d)
	for i in sk.get_bone_count():
		if per_bone[i] > 0.005:
			moved += 1
	return {"bones": moved, "max": peak}
