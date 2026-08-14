extends Node3D
# Force recompile
@onready var tarp_area = $TarpArea
@onready var drop_zone = get_node_or_null("PhysicalTarp/CarcassDropZone")
@onready var timer = $LevelTimer
@onready var spawns = $Spawns
@onready var end_panel = $UILayer/EndPanel
@onready var end_text = $UILayer/EndPanel/EndText

var player: CharacterBody3D
var carcasses_on_tarp: int = 0

func _ready():
	var player_scene = load("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	player.position = Vector3(0, 1, 0)
	add_child(player)
	
	if tarp_area and not tarp_area.get_script():
		tarp_area.set_script(preload("res://scripts/level1_ending.gd"))
		tarp_area.set_process(true)
		tarp_area._ready() # Call _ready manually since it was attached dynamically

	if drop_zone:
		drop_zone.body_entered.connect(_on_drop_zone_body_entered)
		drop_zone.body_exited.connect(_on_drop_zone_body_exited)
	timer.timeout.connect(_on_timeout)
	
	timer.wait_time = 120.0
	timer.start()

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		if tarp_area and player:
			tarp_area._on_body_entered(player)

func _process(_delta):
	var time_left = int(timer.time_left)
	var mins = time_left / 60
	var secs = time_left % 60
	if player and player.has_node("HUD/TimerLabel"):
		player.get_node("HUD/TimerLabel").text = "%d:%02d" % [mins, secs]

func _on_drop_zone_body_entered(body):
	if body.name == "Player":
		body.is_on_tarp = true
		if body.is_carrying_animal:
			var animal_name = body.drop_animal()
			if animal_name != "":
				spawn_dropped_carcass(animal_name)

func _on_drop_zone_body_exited(body):
	if body.name == "Player":
		body.is_on_tarp = false

func spawn_dropped_carcass(animal_name: String):
	var scene = load("res://scenes/" + animal_name + ".tscn")
	if scene:
		var inst = scene.instantiate()
		
		# Create a RigidBody3D to act as the carcass
		var carcass_rb = RigidBody3D.new()
		carcass_rb.add_to_group("carcass")
		
		# Extract collision shape
		var shape = null
		for child in inst.get_children():
			if child is CollisionShape3D:
				shape = child.duplicate()
				break
		if shape:
			carcass_rb.add_child(shape)
		
		# Extract visual meshes
		var mesh_base = inst.get_node_or_null("MeshBase")
		if mesh_base:
			var visual = mesh_base.duplicate()
			carcass_rb.add_child(visual)
		
		add_child(carcass_rb)
		
		# Spawn above the tarp so it falls and triggers the drop zone Area3D
		# drop_zone is used for coordinates
		var offset_x = randf_range(-1.8, 1.8)
		var offset_z = randf_range(-1.8, 1.8)
		carcass_rb.global_position = drop_zone.global_position + Vector3(offset_x, 1.5 + (carcasses_on_tarp * 0.5), offset_z)
		carcass_rb.rotation_degrees = Vector3(0, randf_range(0, 360), 90)
		
		# Free the original instance as it's a CharacterBody3D that can't be used
		inst.queue_free()
		
		carcasses_on_tarp += 1

func _on_timeout():
	if get_node("/root/GameManager").level == 1:
		if tarp_area and player:
			tarp_area._on_body_entered(player)
		return
		
	end_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if get_node("/root/GameManager").level == 2:
		end_text.text = "The whispers grow louder. The dizzying potion wears off.\n\nTransitioning..."
	else:
		end_text.text = "The hallucination ends..."
		
	await get_tree().create_timer(4.0).timeout
	if get_node("/root/GameManager").level == 2:
		get_node("/root/GameManager").level = 3
		get_tree().change_scene_to_file("res://scenes/Level3.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/OutroCutscene.tscn")
