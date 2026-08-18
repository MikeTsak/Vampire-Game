extends MainLoop
## Export validation: open the finished character scene and confirm mesh, rig,
## materials, animations and collision all survived the round trip to disk.

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/characters/skinwalker_new.tscn")
	var n := ps.instantiate()
	var ok := true

	var skel: Skeleton3D = n.get_node_or_null("MeshBase/Skeleton3D")
	print("skeleton      : %d bones" % (0 if skel == null else skel.get_bone_count()))
	ok = ok and skel != null and skel.get_bone_count() == 68

	for i in 3:
		var mi: MeshInstance3D = skel.get_node_or_null("SkinwalkerLOD%d" % i)
		if mi == null:
			print("LOD%d          : MISSING" % i); ok = false; continue
		var mesh: ArrayMesh = mi.mesh
		var mat := mesh.surface_get_material(0)
		print("LOD%d          : %d tris, mat=%s, skin=%d binds, skeleton=%s, range=[%.0f,%.0f]" % [
			i, mesh.get_faces().size() / 3, mat.resource_path.get_file(),
			mi.skin.get_bind_count(), mi.skeleton,
			mi.visibility_range_begin, mi.visibility_range_end])
		ok = ok and mat != null and mi.skin.get_bind_count() == 68

	var ap: AnimationPlayer = n.get_node_or_null("AnimationPlayer")
	var clips := [] if ap == null else Array(ap.get_animation_list())
	print("animations    : %d -> %s" % [clips.size(), str(clips)])
	for c in clips:
		var an := ap.get_animation(c)
		print("   %-12s %.2fs  %2d tracks  loop=%s" % [c, an.length, an.get_track_count(),
			"yes" if an.loop_mode != Animation.LOOP_NONE else "no"])
	ok = ok and clips.size() == 9

	var proxy: Area3D = n.get_node_or_null("HitProxy")
	var shapes := []
	if proxy:
		for c in proxy.get_children():
			shapes.append("%s(%s)" % [c.name, c.shape.get_class()])
	print("collision     : %s" % str(shapes))
	ok = ok and shapes.size() == 3

	# glTF for anyone taking this into a DCC tool. It lands in a .gdignore'd
	# folder: the export drops extracted PNGs next to the .glb, and Godot has
	# no business importing a second copy of a creature it already has natively.
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(n, st)
	if err == OK:
		err = doc.write_to_filesystem(st, "res://models/skinwalker/gltf/skinwalker.glb")
	print("gltf export   : %s" % ("ok" if err == OK else "FAILED err=%d" % err))

	n.free()
	print("VALIDATE: %s" % ("PASS" if ok else "FAIL"))

func _process(_d: float) -> bool:
	return true
