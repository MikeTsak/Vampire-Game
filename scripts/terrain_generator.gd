extends Node3D

@export var size := Vector2(200, 200)
@export var subdivisions := 100
@export var max_height := 2.0
@export var mountain_height := 30.0

var noise = FastNoiseLite.new()
var mesh_instance : MeshInstance3D
var collision_shape : CollisionShape3D
var static_body : StaticBody3D

func _ready():
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4

	generate_terrain()
	generate_road()

	# Spawn Trees
	var tree_scenes = [
		load("res://models/environment/trees/Tree_AleppoPine.tscn"),
		load("res://models/environment/trees/Tree_Fir.tscn"),
		load("res://models/environment/trees/Tree_KermesOak.tscn"),
		load("res://models/environment/trees/Tree_Plane.tscn"),
		load("res://models/environment/trees/Tree_Strawberry.tscn")
	]
	
	for i in range(150):
		var tx = randf_range(-90, 90)
		var tz = randf_range(-90, 90)
		var dist = Vector2(tx, tz).length()
		
		# Don't spawn on the tarp / player start (15-meter radius exclusion)
		if dist < 15.0: continue
		
		# Don't spawn on the road
		var road_center_x = sin(tz * 0.05) * 20.0
		if abs(tx - road_center_x) < 6.0: continue
		
		var ty = get_height_at(tx, tz)
		var random_scene = tree_scenes[randi() % tree_scenes.size()]
		if random_scene:
			var inst = random_scene.instantiate()
			add_child(inst)
			inst.global_position = Vector3(tx, ty, tz)
			inst.rotation_degrees = Vector3(randf_range(-5, 5), randf_range(0, 360), randf_range(-5, 5))

func generate_terrain():
	var plane = PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions

	var st = SurfaceTool.new()
	st.create_from(plane, 0)
	var array_mesh = st.commit()

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(array_mesh, 0)

	var road_radius = 5.0

	for i in range(mdt.get_vertex_count()):
		var v = mdt.get_vertex(i)
		
		# Base noise height
		var h = noise.get_noise_2d(v.x, v.z) * max_height
		
		# Winding dirt road logic (a curved path through the map)
		var road_center_x = sin(v.z * 0.05) * 20.0
		var dist_to_road = abs(v.x - road_center_x)
		var road_factor = clamp(dist_to_road / road_radius, 0.0, 1.0)
		road_factor = road_factor * road_factor * (3.0 - 2.0 * road_factor)
		h = lerp(0.0, h, road_factor)
		
		# 10-meter flat spawn zone
		var dist_to_center = Vector2(v.x, v.z).length()
		if dist_to_center < 10.0:
			h = 0.0
		elif dist_to_center < 15.0:
			var t = (dist_to_center - 10.0) / 5.0
			t = t * t * (3.0 - 2.0 * t) # smoothstep
			h = lerp(0.0, h, t)
		
		# Steep mountains around the edges
		var edge_dist_x = abs(v.x) / (size.x * 0.5)
		var edge_dist_z = abs(v.z) / (size.y * 0.5)
		var edge_factor = max(edge_dist_x, edge_dist_z)
		
		if edge_factor > 0.8:
			var mountain_falloff = (edge_factor - 0.8) / 0.2
			h += pow(mountain_falloff, 2.0) * mountain_height + noise.get_noise_2d(v.x*3.0, v.z*3.0) * 10.0 * mountain_falloff
			
		v.y = h
		
		mdt.set_vertex(i, v)

	array_mesh.clear_surfaces()
	mdt.commit_to_surface(array_mesh)
	
	# Recalculate normals
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.create_from(array_mesh, 0)
	st.generate_normals()
	array_mesh = st.commit()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	
	# Procedural PS1 dirt material
	var mat = StandardMaterial3D.new()
	var dirt_noise = FastNoiseLite.new()
	dirt_noise.frequency = 0.5
	var dirt_tex = NoiseTexture2D.new()
	dirt_tex.noise = dirt_noise
	dirt_tex.width = 64
	dirt_tex.height = 64
	
	mat.albedo_texture = dirt_tex
	mat.albedo_color = Color(0.25, 0.2, 0.15)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(50, 50, 50)
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	# Collision6
	static_body = StaticBody3D.new()
	# Put on collision layer 1, and make sure mask is set
	static_body.collision_layer = 1
	static_body.collision_mask = 15
	add_child(static_body)
	
	collision_shape = CollisionShape3D.new()
	var conc_shape = array_mesh.create_trimesh_shape()
	collision_shape.shape = conc_shape
	static_body.add_child(collision_shape)

func generate_road():
	# The terrain height field already flattens a winding strip for the dirt road
	# (see road_center_x below), but that strip previously used the same material
	# as the rest of the ground, so it wasn't actually visible as a road. Lay a
	# distinct ribbon mesh along that same curve so it reads clearly.
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_width = 3.5
	var step = 4.0
	var z = -size.y * 0.5
	while z < size.y * 0.5:
		var z2 = z + step
		var cx1 = sin(z * 0.05) * 20.0
		var cx2 = sin(z2 * 0.05) * 20.0
		var y1 = get_height_at(cx1, z) + 0.04
		var y2 = get_height_at(cx2, z2) + 0.04
		var a = Vector3(cx1 - half_width, y1, z)
		var b = Vector3(cx1 + half_width, y1, z)
		var c = Vector3(cx2 - half_width, y2, z2)
		var d = Vector3(cx2 + half_width, y2, z2)

		st.set_uv(Vector2(0.0, z * 0.1)); st.add_vertex(a)
		st.set_uv(Vector2(0.0, z2 * 0.1)); st.add_vertex(c)
		st.set_uv(Vector2(1.0, z * 0.1)); st.add_vertex(b)

		st.set_uv(Vector2(1.0, z * 0.1)); st.add_vertex(b)
		st.set_uv(Vector2(0.0, z2 * 0.1)); st.add_vertex(c)
		st.set_uv(Vector2(1.0, z2 * 0.1)); st.add_vertex(d)

		z = z2
	st.generate_normals()
	var road_mesh = st.commit()

	var road_instance = MeshInstance3D.new()
	road_instance.mesh = road_mesh

	var mat = StandardMaterial3D.new()
	var road_noise = FastNoiseLite.new()
	road_noise.frequency = 0.8
	var road_tex = NoiseTexture2D.new()
	road_tex.noise = road_noise
	road_tex.width = 64
	road_tex.height = 64
	mat.albedo_texture = road_tex
	mat.albedo_color = Color(0.42, 0.36, 0.28)
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(3, 20, 1)
	road_instance.material_override = mat
	add_child(road_instance)

func get_height_at(x: float, z: float) -> float:
	var h = noise.get_noise_2d(x, z) * max_height
	
	var road_center_x = sin(z * 0.05) * 20.0
	var dist_to_road = abs(x - road_center_x)
	var road_radius = 5.0
	var road_factor = clamp(dist_to_road / road_radius, 0.0, 1.0)
	road_factor = road_factor * road_factor * (3.0 - 2.0 * road_factor)
	h = lerp(0.0, h, road_factor)
	
	var dist_to_center = Vector2(x, z).length()
	if dist_to_center < 10.0:
		h = 0.0
	elif dist_to_center < 15.0:
		var t = (dist_to_center - 10.0) / 5.0
		t = t * t * (3.0 - 2.0 * t)
		h = lerp(0.0, h, t)
	
	var edge_dist_x = abs(x) / (size.x * 0.5)
	var edge_dist_z = abs(z) / (size.y * 0.5)
	var edge_factor = max(edge_dist_x, edge_dist_z)
	
	if edge_factor > 0.8:
		var mountain_falloff = (edge_factor - 0.8) / 0.2
		h += pow(mountain_falloff, 2.0) * mountain_height + noise.get_noise_2d(x*3.0, z*3.0) * 10.0 * mountain_falloff
	
	return h
