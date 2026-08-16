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
	for i in range(80):
		var r = randf()
		var tree
		if r > 0.7: tree = platanus_scene.instantiate()
		elif r > 0.3: tree = fir_scene.instantiate()
		else: tree = pine_scene.instantiate()
		
		var pos = get_random_pos()
		var valid = false
		for attempt in range(10):
			pos = get_random_pos()
			if pos.length() < 8.0: continue # Small exclusion radius at player spawn
			var road_center_x = sin(pos.z * 0.05) * 20.0
			if abs(pos.x - road_center_x) < 8.0: continue # Avoid dirt road
			if abs(pos.x) < 4.0 and pos.z > -25.0 and pos.z < 5.0: continue # Clear cinematic path
			valid = true
			for p in spawned_positions:
				if pos.distance_to(p) < 15.0:
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
		
	for i in range(30):
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
				baby.position = pos + Vector3(1.5, 0, 1.5)
				baby.position.y = get_floor_height(baby.position.x, baby.position.z)
				add_child(baby)

	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.level >= 2:
		var park = park_scene.instantiate()
		var park_pos = get_random_pos()
		for p_attempt in range(50):
			park_pos = get_random_pos()
			if park_pos.length() > 60.0:
				break
		park_pos.y = get_floor_height(park_pos.x, park_pos.z)
		park.position = park_pos
		park.rotation.y = randf_range(0, TAU)
		add_child(park)

func get_random_pos() -> Vector3:
	return Vector3(randf_range(-100, 100), 0, randf_range(-100, 100))
