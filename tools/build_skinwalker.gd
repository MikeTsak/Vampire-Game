extends MainLoop
## Builds the whole Skinwalker asset: skeleton, three LOD meshes, materials,
## collision proxy, character scene and a preview stage.
##
## Run headless:
##   godot --headless --path <project> --script res://tools/build_skinwalker.gd

const TEX := "res://textures/skinwalker/"
const MDL := "res://models/skinwalker/"
const SCENE_PATH := "res://scenes/characters/skinwalker_new.tscn"
const PREVIEW_PATH := "res://scenes/dev/SkinwalkerPreview.tscn"
const SHOT_PATH := "res://scenes/dev/SkinwalkerShot.tscn"
const ANIM_PATH := "res://animations/skinwalker.res"
## The scene this replaces; Level1-3 reference it by this uid, so it is
## restored into the header after save rather than letting Godot mint a new one.
const KEEP_UID := "uid://yvhkawsto53o"

var bones: Array

func _initialize() -> void:
	# Textures first. The material only stores a path, so a stale imported copy
	# here is harmless -- but the GAME reads the imported .ctex, so reimport
	# after this run (see tools/README.md) or the new pixels will not show up.
	var tex = load("res://tools/sw_tex.gd").new()
	tex.paint_all()
	tex.save_all(TEX)

	var Rig = load("res://tools/sw_rig.gd")
	bones = Rig.build()
	Rig.resolve_tails(bones)
	print("skeleton: %d bones" % bones.size())

	var mat := _material(false)
	# take_over_path makes the in-memory resource adopt the saved path, so the
	# scene references it externally instead of inlining a copy per LOD.
	var mat_path := "res://materials/skinwalker_body.tres"
	ResourceSaver.save(mat, mat_path)
	mat.take_over_path(mat_path)
	ResourceSaver.save(_material(true), "res://materials/skinwalker_body_pbr.tres")

	var anim = load("res://tools/sw_anim.gd").new()
	anim.setup(bones)
	var lib: AnimationLibrary = anim.build_library()
	ResourceSaver.save(lib, ANIM_PATH)
	lib.take_over_path(ANIM_PATH)
	var names := lib.get_animation_list()
	print("animations: %d clips %s" % [names.size(), str(names)])

	var meshes := []
	for lod in 3:
		var mb = load("res://tools/sw_mesh.gd").new()
		mb.setup(bones)
		load("res://tools/sw_body.gd").new().build(mb, bones, lod)
		var mesh: ArrayMesh = mb.commit(mat)
		var mesh_path := MDL + "skinwalker_lod%d.res" % lod
		ResourceSaver.save(mesh, mesh_path)
		mesh.take_over_path(mesh_path)
		meshes.append(mesh)
		print("  LOD%d: %d tris, %d verts" % [lod, mb.tri_count(), mb.v_pos.size()])

	_save_character(meshes)
	_save_preview(meshes)
	print("BUILD_DONE")

# ---------------------------------------------------------------- material

func _material(pbr: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "skinwalker_albedo.png")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Baked AO/skylight rides in the vertex colours -- that is what carries the
	# form under flat lighting, so it stays on in both variants.
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = Color(1, 1, 1)
	m.emission_texture = load(TEX + "skinwalker_emission.png")
	# MULTIPLY, not the default ADD: with ADD the white emission colour is added
	# across the whole surface and the creature glows solid white. Multiplying
	# means only the lit texels in the emission map (the eyes) actually emit.
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission_energy_multiplier = 1.8
	if pbr:
		# Modern read: per-pixel, normal-mapped, texture-driven roughness.
		m.normal_enabled = true
		m.normal_texture = load(TEX + "skinwalker_normal.png")
		m.normal_scale = 1.0
		m.roughness_texture = load(TEX + "skinwalker_roughness.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		# Period read: vertex-lit. A normal map would do nothing per-vertex.
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.roughness = 0.85
	return m

# --------------------------------------------------------------- skeleton

func _skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for b in bones:
		sk.add_bone(b["name"])
	for i in bones.size():
		var par: String = bones[i]["parent"]
		if par != "":
			sk.set_bone_parent(i, sk.find_bone(par))
	for i in bones.size():
		var local: Vector3 = bones[i]["pos"]
		var par: String = bones[i]["parent"]
		if par != "":
			local -= bones[sk.find_bone(par)]["pos"]
		# Identity rest basis: see the note at the top of sw_rig.gd.
		sk.set_bone_rest(i, Transform3D(Basis(), local))
		sk.set_bone_pose_position(i, local)
		sk.set_bone_pose_rotation(i, Quaternion())
		sk.set_bone_pose_scale(i, Vector3.ONE)
	return sk

# ------------------------------------------------------------------ scene

func _save_character(meshes: Array) -> void:
	var root := Node3D.new()
	root.name = "skinwalker_new"
	root.set_script(load("res://scripts/skinwalker_new.gd"))

	var mesh_base := Node3D.new()
	mesh_base.name = "MeshBase"
	root.add_child(mesh_base)

	var sk := _skeleton()
	mesh_base.add_child(sk)
	var skin := sk.create_skin_from_rest_transforms()

	# Manual LOD chain: three separately authored meshes swapped by distance,
	# rather than a decimator that would eat the antler tines first.
	var ranges := [[0.0, 20.0], [20.0, 48.0], [48.0, 0.0]]
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "SkinwalkerLOD%d" % i
		mi.mesh = meshes[i]
		mi.skin = skin
		mi.skeleton = NodePath("..")
		mi.visibility_range_begin = ranges[i][0]
		mi.visibility_range_end = ranges[i][1]
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		sk.add_child(mi)

	root.add_child(_hit_proxy())

	# Autoplay is left empty on purpose. The existing AI script drives the Head
	# bone directly every frame; letting a clip play unasked would fight it.
	# The gameplay layer opts in when it is ready (see the handover notes).
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", load(ANIM_PATH))
	root.add_child(ap)

	_pack(root, SCENE_PATH, KEEP_UID)
	root.free()

## Simple capsule/box proxy matching the hunched posture. Inert on purpose --
## wired to nothing, ready for whatever the gameplay layer wants.
func _hit_proxy() -> Area3D:
	var area := Area3D.new()
	area.name = "HitProxy"
	area.monitoring = false
	area.monitorable = true

	var body := CollisionShape3D.new()
	body.name = "BodyMass"
	var bc := CapsuleShape3D.new()
	bc.radius = 0.34
	bc.height = 1.72
	body.shape = bc
	body.position = Vector3(0, 0.86, -0.06)
	area.add_child(body)

	var torso := CollisionShape3D.new()
	torso.name = "Torso"
	var tc := CapsuleShape3D.new()
	tc.radius = 0.17
	tc.height = 0.62
	torso.shape = tc
	# Laid along Z: the ribcage is horizontal in this hunched stance.
	torso.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.67, 0.01))
	area.add_child(torso)

	var head := CollisionShape3D.new()
	head.name = "Head"
	var hb := BoxShape3D.new()
	hb.size = Vector3(0.20, 0.22, 0.46)
	head.shape = hb
	head.position = Vector3(0, 1.93, -0.72)
	area.add_child(head)
	return area

# ---------------------------------------------------------------- preview

func _save_preview(meshes: Array) -> void:
	var root := Node3D.new()
	root.name = "SkinwalkerPreview"

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.58, 0.60)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.52, 0.58)
	env.ambient_light_energy = 0.62
	we.environment = env
	root.add_child(we)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 1.7
	key.transform = Transform3D().looking_at(Vector3(-0.5, -0.85, 0.55), Vector3.UP)
	root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.80, 0.95)
	fill.transform = Transform3D().looking_at(Vector3(0.8, -0.25, -0.6), Vector3.UP)
	root.add_child(fill)

	# Orbit rig: spin Turntable.rotation.y to change the review angle.
	var turn := Node3D.new()
	turn.name = "Turntable"
	turn.position = Vector3(0, 1.35, -0.25)
	turn.rotation = Vector3(0, deg_to_rad(145.0), 0)
	root.add_child(turn)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 36.0
	cam.position = Vector3(0, 0.30, 4.45)
	cam.rotation = Vector3(deg_to_rad(-3.5), 0, 0)
	turn.add_child(cam)

	var holder := Node3D.new()
	holder.name = "Skinwalker"
	var mesh_base := Node3D.new()
	mesh_base.name = "MeshBase"
	holder.add_child(mesh_base)
	var sk := _skeleton()
	mesh_base.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.name = "SkinwalkerLOD0"
	mi.mesh = meshes[0]
	mi.skin = sk.create_skin_from_rest_transforms()
	mi.skeleton = NodePath("..")
	sk.add_child(mi)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", load(ANIM_PATH))
	holder.add_child(ap)
	root.add_child(holder)

	_pack(root, PREVIEW_PATH, "")

	# Same stage, plus the turnaround driver, launched as a game to dodge the
	# editor's resource cache.
	root.set_script(load("res://tools/sw_shot.gd"))
	_pack(root, SHOT_PATH, "")
	root.free()

# ------------------------------------------------------------------ saving

func _set_owner(n: Node, own: Node) -> void:
	for c in n.get_children():
		c.owner = own
		_set_owner(c, own)

func _pack(root: Node, path: String, keep_uid: String) -> void:
	_set_owner(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s (%d)" % [path, err])
		return
	_rewrite_uids(path, keep_uid)
	print("  saved %s" % path)

## ResourceSaver writes neither a scene uid nor uids on ext_resource lines.
## Both are patched back in here: the scene keeps the uid the level files
## already reference, and each dependency gets its real uid so the editor
## resolves it directly instead of falling back to path and warning.
func _rewrite_uids(path: String, keep_uid: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()

	if keep_uid != "":
		var nl := text.find("\n")
		var header := text.substr(0, nl)
		if header.contains("uid="):
			var rx := RegEx.new()
			rx.compile('uid="[^"]+"')
			header = rx.sub(header, 'uid="%s"' % keep_uid)
		else:
			header = header.trim_suffix("]") + ' uid="%s"]' % keep_uid
		text = header + text.substr(nl)

	var ext := RegEx.new()
	ext.compile('ext_resource type="(?<t>[^"]+)" path="(?<p>[^"]+)" id="(?<i>[^"]+)"')
	var out := ""
	var cursor := 0
	for mm in ext.search_all(text):
		var dep: String = mm.get_string("p")
		var id := ResourceLoader.get_resource_uid(dep)
		out += text.substr(cursor, mm.get_start() - cursor)
		if id != ResourceUID.INVALID_ID:
			out += 'ext_resource type="%s" uid="%s" path="%s" id="%s"' % [
				mm.get_string("t"), ResourceUID.id_to_text(id), dep, mm.get_string("i")]
		else:
			out += mm.get_string()
		cursor = mm.get_end()
	out += text.substr(cursor)

	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(out)
	f.close()

func _process(_d: float) -> bool:
	return true
