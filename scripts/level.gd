extends Node3D
# Force recompile
@onready var timer = get_node_or_null("LevelTimer")
@onready var spawns = get_node_or_null("Spawns")
@onready var end_panel = get_node_or_null("UILayer/EndPanel")
@onready var end_text = get_node_or_null("UILayer/EndPanel/EndText")

var player: CharacterBody3D
var carcasses_on_tarp: int = 0
var level_ended: bool = false

func _ready():
	var player_scene = load("res://scenes/characters/Player.tscn")
	player = player_scene.instantiate()
	player.position = Vector3(0, 1, 0)
	add_child(player)

	# Spawn initial animals (pack spawning: babies join adults from level 2 onward)
	if spawns:
		var deer_scene = load("res://scenes/animals/Deer2.tscn")
		var sheep_scene = load("res://scenes/animals/Sheep2.tscn")
		var baby_deer_scene = load("res://scenes/animals/BabyDeer_new.tscn")
		var baby_sheep_scene = load("res://scenes/animals/BabySheep.tscn")
		var gm = get_node_or_null("/root/GameManager")
		var pack_spawning = gm != null and gm.level >= 2

		for marker in spawns.get_children():
			if marker is Marker3D:
				var is_sheep = randi() % 2 == 0
				var animal_scene = sheep_scene if is_sheep else deer_scene
				if not animal_scene:
					continue
				var animal = animal_scene.instantiate()
				add_child(animal)
				# Defer setting global position to avoid tree errors during _ready, or use position
				animal.position = spawns.position + marker.position
				# Add some random rotation
				animal.rotation_degrees.y = randf_range(0, 360)

				if pack_spawning:
					var baby_scene = baby_sheep_scene if is_sheep else baby_deer_scene
					if baby_scene:
						var baby = baby_scene.instantiate()
						add_child(baby)
						baby.position = animal.position + Vector3(1.2, 0, 1.2)
						baby.rotation_degrees.y = randf_range(0, 360)

	timer.timeout.connect(_on_timeout)

	timer.wait_time = 120.0
	timer.start()

func _process(_delta):
	var time_left = int(timer.time_left)
	var mins = time_left / 60
	var secs = time_left % 60
	if player and player.has_node("HUD/TimerLabel"):
		player.get_node("HUD/TimerLabel").text = "%d:%02d" % [mins, secs]

func _unhandled_input(event):
	# Debug: F10 force-ends the current level immediately, same path as a natural timeout
	# (Level1 -> MidCutscene -> Level2, Level2 -> Level3, Level3 -> OutroCutscene).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		if timer:
			timer.stop()
		_on_timeout()

func _on_timeout():
	if level_ended:
		return
	level_ended = true
	var gm = get_node_or_null("/root/GameManager")
	var current_level = gm.level if gm else 1

	if end_panel:
		end_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var next_scene = ""
	if current_level == 1:
		if end_text: end_text.text = "The night is over. Time to collect your pay...\n\nTransitioning..."
		next_scene = "res://scenes/cutscenes/MidCutscene.tscn"
	elif current_level == 2:
		if end_text: end_text.text = "The whispers grow louder. The dizzying potion wears off.\n\nTransitioning..."
		next_scene = "res://scenes/levels/Level3.tscn"
	else:
		if end_text: end_text.text = "The hallucination ends..."
		next_scene = "res://scenes/cutscenes/OutroCutscene.tscn"

	await get_tree().create_timer(4.0).timeout

	if gm and current_level == 2:
		gm.level = 3

	get_tree().change_scene_to_file(next_scene)
