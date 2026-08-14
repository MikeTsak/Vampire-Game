extends Node3D

var tex_closed = preload("res://textures/face.png")
var tex_open = preload("res://textures/face-open.png")
var is_talking = false
var head_material : StandardMaterial3D = null

func _ready():
	var head = get_node_or_null("Torso/Neck/Head")
	if head and head.material:
		head_material = head.material
	# Just to ensure color is white
	if head_material:
		head_material.albedo_color = Color(1, 1, 1, 1)

func start_talking():
	if is_talking: return
	is_talking = true
	_talk_loop()

func _talk_loop():
	var toggle = false
	while is_talking:
		if head_material:
			head_material.albedo_texture = tex_open if toggle else tex_closed
		toggle = not toggle
		await get_tree().create_timer(0.15).timeout
	if head_material:
		head_material.albedo_texture = tex_closed

func stop_talking():
	is_talking = false
	if head_material:
		head_material.albedo_texture = tex_closed
