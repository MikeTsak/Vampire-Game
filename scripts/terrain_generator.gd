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
