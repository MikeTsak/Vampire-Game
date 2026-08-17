extends Node3D
# Force recompile
var fir_scene = preload("res://scenes/environment/FirTree.tscn")
var pine_scene = preload("res://scenes/environment/PineTree.tscn")
var platanus_scene = load("res://scenes/environment/PlatanusTree.tscn")
var rock_scene = preload("res://scenes/environment/Rock.tscn")
var sheep_scene = preload("res://scenes/animals/Sheep2.tscn")
var deer_scene = preload("res://scenes/animals/Deer2.tscn")
var park_scene = preload("res://scenes/environment/ParkOfSouls.tscn")

func _ready():
	randomize()
	await get_tree().physics_frame
	spawn_environment()

func get_floor_height(x: float, z: float) -> float:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3(x, 100, z), Vector3(x, -100, z))
	var result = space_state.intersect_ray(query)
	if result:
		return result.position.y
	
	var terrain_generator = get_node_or_null("../TerrainGenerator")
	if terrain_generator and terrain_generator.has_method("get_height_at"):
		return terrain_generator.get_height_at(x, z)
	return 0.0


func spawn_environment():
	var spawned_positions = []
	for i in range(500):
		var r = randf()
		var tree
		if r > 0.7: tree = platanus_scene.instantiate()
		elif r > 0.3: tree = fir_scene.instantiate()
		else: tree = pine_scene.instantiate()
		
		var pos = get_random_pos()
		var valid = false
		for attempt in range(15):
			pos = get_random_pos()
			if pos.length() < 8.0: continue # Small exclusion radius at player spawn
			var road_center_x = sin(pos.z * 0.05) * 20.0
			if abs(pos.x - road_center_x) < 8.0: continue # Avoid dirt road
			if abs(pos.x) < 4.0 and pos.z > -25.0 and pos.z < 5.0: continue # Clear cinematic path
			valid = true
			for p in spawned_positions:
				if pos.distance_to(p) < 6.0:
					valid = false
					break
			if valid: break
			
		if not valid: continue
		spawned_positions.append(pos)
			
		pos.y = get_floor_height(pos.x, pos.z)
		tree.position = pos
		tree.rotation.y = randf_range(0, TAU)
		add_child(tree)
		
	for i in range(150):
		var rock = rock_scene.instantiate()
		var pos = get_random_pos()
		if pos.length() < 8.0: continue
		var road_center_x = sin(pos.z * 0.05) * 20.0
		if abs(pos.x - road_center_x) < 8.0: continue
		if abs(pos.x) < 4.0 and pos.z > -25.0 and pos.z < 5.0: continue
		
		pos.y = get_floor_height(pos.x, pos.z)
		rock.position = pos
		rock.rotation.y = randf_range(0, TAU)
		rock.scale = Vector3.ONE * randf_range(0.5, 2.0)
		add_child(rock)
		
	for i in range(8):
		var is_sheep = randf() > 0.5
		var animal = sheep_scene.instantiate() if is_sheep else deer_scene.instantiate()
		var pos = get_random_pos()
		if pos.length() < 15.0: pos = get_random_pos()
		var road_center_x = sin(pos.z * 0.05) * 20.0
		if abs(pos.x - road_center_x) < 8.0: pos = get_random_pos()
		if abs(pos.x) < 4.0 and pos.z > -25.0 and pos.z < 5.0: pos = get_random_pos()

		pos.y = get_floor_height(pos.x, pos.z)
		animal.position = pos
		add_child(animal)

		var gm = get_node_or_null("/root/GameManager")
		if gm and gm.level >= 2:
			var baby_scene = load("res://scenes/animals/BabySheep.tscn") if is_sheep else load("res://scenes/animals/BabyDeer_new.tscn")
			if baby_scene:
				var baby = baby_scene.instantiate()
				# Keep the little ones a genuine short walk from the adult, tucked
				# further into the forest rather than sitting right beside it.
				var baby_angle = randf_range(0, TAU)
				var baby_dist = randf_range(10.0, 16.0)
				baby.position = pos + Vector3(cos(baby_angle) * baby_dist, 0, sin(baby_angle) * baby_dist)
				baby.position.y = get_floor_height(baby.position.x, baby.position.z)
				add_child(baby)

	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.level >= 2:
		var park = park_scene.instantiate()
		park.name = "ParkOfSouls"
		# Anywhere is fine -- just keep it off the sanatorium's side of the map
		# (the sanatorium sits in the -Z half, around world z=-140).
		var park_pos = get_random_pos()
		for attempt in range(60):
			park_pos = get_random_pos()
			if park_pos.z > 40.0:
				break
		if park_pos.z <= 40.0:
			# Couldn't roll a spot on the far side after all retries -- force it
			# there deterministically so it never ends up near the sanatorium.
			park_pos = Vector3(0, 0, 70)
		park_pos.y = get_floor_height(park_pos.x, park_pos.z)
		park.position = park_pos
		_orient_toward_tarp(park, park_pos)
		add_child(park)

	# Safety net: some dev/testing workflows launch Level2 directly without
	# going through GameManager progression, so gm.level never reaches 2 and
	# the gated block above gets skipped entirely. Guarantee the Park of
	# Souls still exists whenever this generator is actually running inside
	# Level2, regardless of how the scene was reached.
	var level_root = get_parent()
	if level_root and level_root.name == "Level2" and not level_root.find_child("ParkOfSouls", true, false):
		var fallback_park = park_scene.instantiate()
		fallback_park.name = "ParkOfSouls"
		var fallback_pos = Vector3(0, 0, 70)
		fallback_pos.y = get_floor_height(fallback_pos.x, fallback_pos.z)
		fallback_park.position = fallback_pos
		_orient_toward_tarp(fallback_park, fallback_pos)
		add_child(fallback_park)

func _orient_toward_tarp(node: Node3D, node_pos: Vector3):
	# The park's gate/archway sits on the model's local +Z side, which is the
	# opposite of Godot's default -Z "forward" -- always rotate the park so
	# that side faces the tarp/spawn point, no matter where it lands.
	var level_root = get_parent()
	var tarp_node = level_root.get_node_or_null("Tarp") if level_root else null
	var tarp_pos = tarp_node.position if tarp_node else Vector3(0, 0, -4)
	if node_pos.distance_to(tarp_pos) > 0.01:
		var facing_tarp = Transform3D(Basis(), node_pos).looking_at(tarp_pos, Vector3.UP)
		node.rotation.y = facing_tarp.basis.get_euler().y + PI

func get_random_pos() -> Vector3:
	# Match the actual configured terrain size instead of a hardcoded range --
	# this was previously fixed at +-100 regardless of level, which left the
	# outer ring of a larger map (Level2 is 300x300) completely unpopulated.
	var half_extent = 90.0
	var terrain_generator = get_node_or_null("../TerrainGenerator")
	if terrain_generator:
		half_extent = min(terrain_generator.size.x, terrain_generator.size.y) * 0.5 * 0.9
	return Vector3(randf_range(-half_extent, half_extent), 0, randf_range(-half_extent, half_extent))
