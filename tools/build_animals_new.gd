extends MainLoop
## Turns the generated glTF animals into game-ready scenes.
##
## tools/gen_animals_new.py authors the geometry, atlas, armature and clips and
## drops a manifest beside them; this reads what Godot imported and assembles
## the playable side of it -- collision proxy, PS1 material, animation library
## and the CharacterBody3D wrapper the rest of the game expects.
##
## Run headless:
##   godot --headless --path <project> --script res://tools/build_animals_new.gd

const MANIFEST := "res://models/animals/animals_new.json"
const SCRIPT_PATH := "res://scripts/animal_new.gd"
const LOOPING := ["idle", "walk"]
const REQUIRED := ["idle", "walk", "death"]
const PREVIEW_PATH := "res://scenes/dev/AnimalsNewPreview.tscn"
const PREVIEW_SCRIPT := "res://scripts/animals_preview.gd"
const SPACING := 2.6

func _initialize() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_error("no manifest at %s -- run tools/gen_animals_new.py first" % MANIFEST)
		return
	var entries: Array = JSON.parse_string(f.get_as_text())
	f.close()

	print("building %d animal scenes" % entries.size())
	for e in entries:
		_build(e)
	_save_preview(entries)

func _build(e: Dictionary) -> void:
	var name: String = e["name"]
	var packed := load(e["gltf"]) as PackedScene
	if packed == null:
		push_error("%s: could not load %s" % [name, e["gltf"]])
		return
	var src := packed.instantiate()

	var sk := _first(src, "Skeleton3D") as Skeleton3D
	var mi := _first(src, "MeshInstance3D") as MeshInstance3D
	var ap_src := _first(src, "AnimationPlayer") as AnimationPlayer
	if sk == null or mi == null or ap_src == null:
		push_error("%s: import is missing skeleton, mesh or animations" % name)
		src.free()
		return

	# Godot serves imported scenes from .godot/imported. If the glTF was
	# regenerated without a re-import, the build would silently assemble the
	# previous model, so the bounds are checked against the fresh manifest.
	var aabb := (mi.mesh as ArrayMesh).get_aabb()
	if absf(aabb.size.y - float(e["mesh_height"])) > 0.01 or absf(aabb.size.z - float(e["mesh_length"])) > 0.01:
		push_error(("%s: the imported mesh is %.2fx%.2f but the manifest says %.2fx%.2f -- re-import res://models/animals/ before building")
			% [name, aabb.size.y, aabb.size.z, e["mesh_height"], e["mesh_length"]])
		src.free()
		return

	var mat := _material(name, e["atlas"])
	var mesh := _clean_mesh(name, mi.mesh as ArrayMesh, mat)
	var lib := _library(name, ap_src)
	if mesh == null or lib == null:
		src.free()
		return

	# -- scene ---------------------------------------------------------------
	var root := CharacterBody3D.new()
	root.name = name
	root.set_script(load(SCRIPT_PATH))
	root.set("score_value", int(e["score_value"]))
	root.set("walk_cycle_distance", float(e["walk_cycle_distance"]))

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	var size: Array = e["collider_size"]
	box.size = Vector3(size[0], size[1], size[2])
	col.shape = box
	col.position = Vector3(0.0, e["collider_y"], e["collider_z"])
	root.add_child(col)

	# animal.gd hands "MeshBase" to the carcass on death, so the whole visual
	# rig -- skeleton, mesh and player -- has to live under that one node.
	var mesh_base := Node3D.new()
	mesh_base.name = "MeshBase"
	root.add_child(mesh_base)

	sk.get_parent().remove_child(sk)
	sk.owner = null            # still points at the imported root otherwise
	mesh_base.add_child(sk)
	sk.name = "Skeleton3D"
	mi.name = "%s_mesh" % name
	mi.mesh = mesh
	mi.skeleton = NodePath("..")

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", lib)
	# root_node defaults to "..", i.e. MeshBase, which is what the imported
	# "Skeleton3D:<bone>" track paths are relative to.
	mesh_base.add_child(ap)

	src.free()
	_pack(root, e["scene"])
	root.free()

	print("  %-16s %d tris, %d bones, %d clips -> %s"
		% [name, e["tris"], e["bones"], REQUIRED.size(), e["scene"]])

# ------------------------------------------------------------------- pieces

## PS1 surface: unfiltered atlas, no specular highlight, nothing that would
## betray the flat-shaded low-poly silhouette.
func _material(name: String, atlas: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(atlas)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = name
	var path := "res://materials/%s.tres" % name
	var err := ResourceSaver.save(m, path)
	if err != OK:
		push_error("material save failed %s (%d)" % [path, err])
	return load(path)

## Rebuilt from the imported surface arrays: the scene importer bakes LODs and
## a shadow mesh into every import, and on a 300-triangle animal both are pure
## overhead. Bones, weights and UVs come across untouched.
func _clean_mesh(name: String, src_mesh: ArrayMesh, mat: Material) -> ArrayMesh:
	if src_mesh == null or src_mesh.get_surface_count() == 0:
		push_error("%s: imported mesh has no surfaces" % name)
		return null
	var arrays := src_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	if verts.size() == 0 or bones == null or bones.size() == 0:
		push_error("%s: imported mesh lost its skin weights" % name)
		return null

	var flags := 0
	if bones.size() / verts.size() == 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS

	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	out.surface_set_material(0, mat)
	out.resource_name = name
	var path := "res://models/animals/%s_mesh.res" % name
	var err := ResourceSaver.save(out, path)
	if err != OK:
		push_error("mesh save failed %s (%d)" % [path, err])
		return null
	return load(path)

## glTF carries no loop flag, so the importer marks every clip one-shot. Idle
## and walk are cycles and have to say so; death must not restart.
func _library(name: String, ap: AnimationPlayer) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for clip in REQUIRED:
		if not ap.has_animation(clip):
			push_error("%s: import has no '%s' animation" % [name, clip])
			return null
		var anim: Animation = ap.get_animation(clip).duplicate(true)
		if clip in LOOPING:
			anim.loop_mode = Animation.LOOP_LINEAR
		else:
			anim.loop_mode = Animation.LOOP_NONE
		anim.resource_name = clip
		lib.add_animation(clip, anim)
	var path := "res://animations/%s.res" % name
	var err := ResourceSaver.save(lib, path)
	if err != OK:
		push_error("animation save failed %s (%d)" % [path, err])
		return null
	return load(path)

# ------------------------------------------------------------------- saving

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

## ResourceSaver writes neither a scene uid nor uids on ext_resource lines.
## Both get patched in so the editor resolves dependencies directly instead of
## falling back to path and warning. Same treatment tools/build_skinwalker.gd
## gives its scenes.
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

# ------------------------------------------------------------------ preview

## A dev stage holding the whole family in a row, for eyeballing silhouettes,
## texture seams and scale against each other. Not shipped with any level.
func _save_preview(entries: Array) -> void:
	var root := Node3D.new()
	root.name = "AnimalsNewPreview"
	root.set_script(load(PREVIEW_SCRIPT))

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e3 := Environment.new()
	e3.background_mode = Environment.BG_COLOR
	e3.background_color = Color(0.09, 0.10, 0.12)
	e3.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e3.ambient_light_color = Color(0.42, 0.45, 0.52)
	e3.ambient_light_energy = 1.0
	env.environment = e3
	root.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis(), Vector3(0, 6, 0)).looking_at(
		Vector3(-3, 0, -4), Vector3.UP)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.22, 0.18)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.transform = Transform3D(Basis(), Vector3(0.0, 2.4, 10.5)).looking_at(
		Vector3(0.0, 0.75, 0.0), Vector3.UP)
	root.add_child(cam)

	var span := SPACING * float(entries.size() - 1) * 0.5
	for i in entries.size():
		var e: Dictionary = entries[i]
		var packed := load(e["scene"]) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		inst.name = e["name"]
		inst.position = Vector3(SPACING * float(i) - span, 0.0, 0.0)
		# quarter-turn so both flank and three-quarter face read in one shot
		inst.rotation.y = deg_to_rad(-35.0)
		root.add_child(inst)

	# instanced children keep their own scenes: only the nodes this function
	# creates get owned, or packing would flatten the animals into the stage
	for c in root.get_children():
		c.owner = root
		if not c.scene_file_path:
			_set_owner(c, root)

	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, PREVIEW_PATH)
	if err != OK:
		push_error("preview save failed (%d)" % err)
	else:
		_rewrite_uids(PREVIEW_PATH)
		print("  preview -> %s" % PREVIEW_PATH)
	root.free()

func _process(_d: float) -> bool:
	return true
