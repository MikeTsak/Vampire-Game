extends MainLoop
## Assembles the player's shadow body into a scene the Player can instance.
##
## tools/gen_player_shadow_new.py authors the geometry, armature and clips; this
## turns the import into a shadows-only rig with its driver attached.
##
## Run headless:
##   godot --headless --path <project> --script res://tools/build_player_shadow_new.gd

const GLTF := "res://models/player/player_shadow_new.gltf"
const SCENE := "res://scenes/characters/player_shadow_new.tscn"
const DRIVER := "res://scripts/player_shadow_new.gd"
const MESH_RES := "res://models/player/player_shadow_new_mesh.res"
const ANIM_RES := "res://animations/player_shadow_new.res"
const CLIPS := ["idle", "walk", "run", "aim"]
const PREVIEW := "res://scenes/dev/PlayerShadowPreview.tscn"

func _initialize() -> void:
	var packed := load(GLTF) as PackedScene
	if packed == null:
		push_error("could not load %s -- run the generator and re-import" % GLTF)
		return
	var src := packed.instantiate()

	var sk := _first(src, "Skeleton3D") as Skeleton3D
	var mi := _first(src, "MeshInstance3D") as MeshInstance3D
	var ap_src := _first(src, "AnimationPlayer") as AnimationPlayer
	if sk == null or mi == null or ap_src == null:
		push_error("import is missing skeleton, mesh or animations")
		src.free()
		return

	var mesh := _clean_mesh(mi.mesh as ArrayMesh)
	var lib := _library(ap_src)
	if mesh == null or lib == null:
		src.free()
		return

	var root := Node3D.new()
	root.name = "player_shadow_new"
	root.set_script(load(DRIVER))

	sk.get_parent().remove_child(sk)
	sk.owner = null
	root.add_child(sk)
	sk.name = "Skeleton3D"
	mi.name = "ShadowBody"
	mi.mesh = mesh
	mi.skeleton = NodePath("..")
	# The whole point: geometry that exists only to interrupt light.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", lib)
	# root_node defaults to "..", the scene root, which is what the imported
	# "Skeleton3D:<bone>" track paths are relative to.
	root.add_child(ap)

	src.free()
	var bone_count := sk.get_bone_count()
	_pack(root, SCENE)
	root.free()
	print("player shadow: %d bones, %d clips -> %s"
		% [bone_count, CLIPS.size(), SCENE])
	_save_preview()

# ----------------------------------------------------------------- preview

## A lit stage for eyeballing the shadow: one copy drawn solid so the model
## can be judged, one shadows-only beside it so the silhouette it actually
## throws can be judged too. Not shipped with any level.
func _save_preview() -> void:
	var root := Node3D.new()
	root.name = "PlayerShadowPreview"

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.33, 0.40)
	e.ambient_light_energy = 1.0
	env.environment = e
	root.add_child(env)

	# low and off to one side, so the shadow is thrown long across the floor
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis(), Vector3(-2.6, 3.4, -2.2)).looking_at(
		Vector3(0, 0.9, 0), Vector3.UP)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.44, 0.40)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.transform = Transform3D(Basis(), Vector3(0.4, 3.9, 5.2)).looking_at(
		Vector3(0.5, 0.4, 0.6), Vector3.UP)
	root.add_child(cam)

	var packed := load(SCENE) as PackedScene

	# solid copy, so the model itself can be inspected. Unskinned, so it
	# shows the bind pose -- which is the carry pose.
	var solid := MeshInstance3D.new()
	solid.name = "Solid"
	solid.mesh = load(MESH_RES)
	solid.position = Vector3(-1.9, 0, 0)
	solid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.62, 0.60, 0.56)
	sm.roughness = 1.0
	solid.material_override = sm
	root.add_child(solid)

	# and the real thing, exactly as the Player carries it
	var caster := packed.instantiate()
	caster.name = "ShadowOnly"
	caster.position = Vector3(1.1, 0, 0)
	root.add_child(caster)

	for c in root.get_children():
		c.owner = root
		if not c.scene_file_path:
			_own(c, root)

	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, PREVIEW)
	if err != OK:
		push_error("preview save failed (%d)" % err)
	else:
		_rewrite_uids(PREVIEW)
		print("  preview -> %s" % PREVIEW)
	root.free()

func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _meshes(c)
	return out

func _own(n: Node, own: Node) -> void:
	for c in n.get_children():
		c.owner = own
		_own(c, own)


## Rebuilt from the surface arrays to drop the LODs and shadow mesh the scene
## importer bakes in. A shadow caster wants neither.
func _clean_mesh(src_mesh: ArrayMesh) -> ArrayMesh:
	if src_mesh == null or src_mesh.get_surface_count() == 0:
		push_error("imported mesh has no surfaces")
		return null
	var arrays := src_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	if verts.size() == 0 or bones == null or bones.size() == 0:
		push_error("imported mesh lost its skin weights")
		return null
	var flags := 0
	if bones.size() / verts.size() == 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS

	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	# Never rasterised into the colour buffer, so the material only has to be
	# cheap and opaque.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.12)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	out.surface_set_material(0, m)
	out.resource_name = "player_shadow_new"
	var err := ResourceSaver.save(out, MESH_RES)
	if err != OK:
		push_error("mesh save failed (%d)" % err)
		return null
	return load(MESH_RES)

## Every clip here is a held state, so all four loop.
func _library(ap: AnimationPlayer) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for clip in CLIPS:
		if not ap.has_animation(clip):
			push_error("import has no '%s' animation" % clip)
			return null
		var anim: Animation = ap.get_animation(clip).duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR
		anim.resource_name = clip
		lib.add_animation(clip, anim)
	var err := ResourceSaver.save(lib, ANIM_RES)
	if err != OK:
		push_error("animation save failed (%d)" % err)
		return null
	return load(ANIM_RES)

func _first(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _first(c, cls)
		if r != null:
			return r
	return null

func _set_owner(n: Node, own: Node) -> void:
	for c in n.get_children():
		c.owner = own
		_set_owner(c, own)

func _pack(root: Node, path: String) -> void:
	_set_owner(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s (%d)" % [path, err])
		return
	_rewrite_uids(path)

## ResourceSaver writes neither a scene uid nor uids on ext_resource lines;
## both are patched back in so the editor resolves dependencies directly.
func _rewrite_uids(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()

	var uid := ResourceLoader.get_resource_uid(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	if ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, path)
	else:
		ResourceUID.add_id(uid, path)

	var nl := text.find("\n")
	var header := text.substr(0, nl)
	if not header.contains("uid="):
		header = header.trim_suffix("]") + ' uid="%s"]' % ResourceUID.id_to_text(uid)
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
				mm.get_string("t"), ResourceUID.id_to_text(id), dep,
				mm.get_string("i")]
		else:
			out += mm.get_string()
		cursor = mm.get_end()
	out += text.substr(cursor)

	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(out)
	f.close()

func _process(_d: float) -> bool:
	return true
