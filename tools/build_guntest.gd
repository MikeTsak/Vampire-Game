extends MainLoop
## Builds scenes/dev/GunTest.tscn -- a floor, a wall to catch the muzzle light,
## and the real Player scene, driven by tools/gun_shot.gd.

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "GunTest"
	root.set_script(load("res://tools/gun_shot.gd"))

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.25, 0.32)
	env.ambient_light_energy = 0.5
	we.environment = env
	root.add_child(we)

	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_energy = 0.35
	key.transform = Transform3D().looking_at(Vector3(-0.4, -0.8, -0.5), Vector3.UP)
	root.add_child(key)

	# Floor.
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(40, 1, 40)
	fs.shape = fb
	fs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fs)
	var fm := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(40, 1, 40)
	fm.mesh = fmesh
	fm.position = Vector3(0, -0.5, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.20, 0.19, 0.17)
	fm.material_override = fmat
	floor_body.add_child(fm)
	root.add_child(floor_body)

	# Wall ahead, so the muzzle flash has something to light up.
	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(9, 5, 0.4)
	wall.mesh = wmesh
	wall.position = Vector3(0, 2.5, -4.5)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.30, 0.27, 0.24)
	wall.material_override = wmat
	root.add_child(wall)

	var player: Node = load("res://scenes/characters/Player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)

	for c in root.get_children():
		c.owner = root
		if c.scene_file_path == "":
			for g in c.get_children():
				g.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	print("save err=%d" % ResourceSaver.save(ps, "res://scenes/dev/GunTest.tscn"))
	root.free()

func _process(_d: float) -> bool:
	return true
