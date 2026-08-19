extends Node3D
# Force recompile

## Which level this scene is. GameManager.level is set from this on load, so it
## is correct no matter how the level was entered -- normal progression, the
## main menu's Debug Level 2 button, or running the .tscn straight from the
## editor. Those shortcuts previously left GameManager.level at 1, which meant
## no pack spawning and a skinwalker that could never arm.
@export var level_number: int = 1

## Interior levels spawn from room anchors under "Rooms" instead of the flat
## "Spawns" marker list, and keep packs tight enough to stay behind one door.
@export var indoor: bool = false
## Adults dropped into each ward room. Their young are separate, see baby_chance.
@export var animals_per_room: int = 1
## Odds an adult gets a calf/lamb with it. Only applies from level 2 onward.
@export var baby_chance: float = 0.55
## Odds any given room has anything in it at all. Below 1.0 some rooms come up
## empty, which is the whole point of clearing them one at a time.
@export var room_occupancy: float = 1.0

## Carcasses that must be lying on the tarp before the level ends. 0 leaves the
## level on the clock instead, which is how levels 1 and 2 work.
@export var carcass_quota: int = 0

## Which way the player is looking when they spawn on the tarp. Outdoors it does
## not matter; indoors it decides whether they open on the corridor or on a wall.
@export var player_start_yaw_degrees: float = 0.0

## The Parnitha bestiary, rigged and animated by tools/gen_animals_new.py.
## Weights are draw odds out of the total: boar are the rare encounter, and
## worth more when they do turn up.
const SPECIES := [
	{"adult": "res://scenes/animals/deer_new.tscn",
	 "young": "res://scenes/animals/baby_deer_new.tscn", "weight": 4},
	{"adult": "res://scenes/animals/sheep_new.tscn",
	 "young": "res://scenes/animals/baby_sheep_new.tscn", "weight": 4},
	{"adult": "res://scenes/animals/boar_new.tscn",
	 "young": "res://scenes/animals/baby_boar_new.tscn", "weight": 2},
]

## Weighted draw from SPECIES.
func _pick_species() -> Dictionary:
	var total := 0
	for s in SPECIES:
		total += int(s["weight"])
	var roll := randi() % total
	for s in SPECIES:
		roll -= int(s["weight"])
		if roll < 0:
			return s
	return SPECIES[0]

@onready var timer = get_node_or_null("LevelTimer")
@onready var spawns = get_node_or_null("Spawns")
@onready var rooms = get_node_or_null("Rooms")
@onready var end_panel = get_node_or_null("UILayer/EndPanel")
@onready var end_text = get_node_or_null("UILayer/EndPanel/EndText")

var player: CharacterBody3D
var carcasses_on_tarp: int = 0
var level_ended: bool = false

func _get_tarp_position() -> Vector3:
	var tarp = get_node_or_null("Tarp")
	return tarp.position if tarp else Vector3.ZERO

func _ready():
	# Do this first: the pack-spawning check below and the forest generator both
	# read GameManager.level.
	var gm_init = get_node_or_null("/root/GameManager")
	if gm_init and "level" in gm_init:
		gm_init.level = level_number

	var player_scene = load("res://scenes/characters/Player.tscn")
	player = player_scene.instantiate()
	# Spawn on the tarp itself so the player never starts overlapping procedural
	# forest geometry (trees/rocks) placed elsewhere in the level.
	player.position = _get_tarp_position() + Vector3(0, 1, 0)
	player.rotation.y = deg_to_rad(player_start_yaw_degrees)
	add_child(player)

	var gm = get_node_or_null("/root/GameManager")
	if indoor and rooms:
		_spawn_indoors(gm)
	elif spawns:
		_spawn_outdoors(gm)

	timer.timeout.connect(_on_timeout)

	if carcass_quota > 0:
		# Quota-driven level: the tarp is the trigger, not the clock.
		timer.stop()
		_update_quota_hud()
	else:
		timer.wait_time = 120.0
		timer.start()

## Flat marker list scattered across open terrain. Packs spread wide because
## there is nothing out there to walk into.
func _spawn_outdoors(gm) -> void:
	var pack_spawning = gm != null and gm.level >= 2

	for marker in spawns.get_children():
		if marker is Marker3D:
			var species = _pick_species()
			var animal_scene = load(species["adult"])
			if not animal_scene:
				continue
			var animal = animal_scene.instantiate()
			add_child(animal)
			# Defer setting global position to avoid tree errors during _ready, or use position
			animal.position = spawns.position + marker.position
			# Add some random rotation
			animal.rotation_degrees.y = randf_range(0, 360)

			if pack_spawning:
				var baby_scene = load(species["young"])
				if baby_scene:
					var baby = baby_scene.instantiate()
					add_child(baby)
					# Keep the little ones a genuine short walk from the adult
					# rather than glued right next to it.
					var baby_angle = randf_range(0, TAU)
					var baby_dist = randf_range(10.0, 16.0)
					baby.position = animal.position + Vector3(cos(baby_angle) * baby_dist, 0, sin(baby_angle) * baby_dist)
					baby.rotation_degrees.y = randf_range(0, 360)

## Interior spawning. Each Marker3D under "Rooms" is one ward room, carrying a
## "room_extents" half-size in metadata; animals are dropped at random points
## inside that footprint so no two runs clear the wing in the same order. Young
## stay in the same room as the adult -- the outdoor 10-16m pack spread would
## put them straight through a wall.
func _spawn_indoors(gm) -> void:
	var pack_spawning = gm != null and gm.level >= 2

	for marker in rooms.get_children():
		if not (marker is Marker3D):
			continue
		if randf() > room_occupancy:
			continue
		var extents: Vector2 = marker.get_meta("room_extents", Vector2(4.0, 4.0))
		for _i in range(animals_per_room):
			var species = _pick_species()
			var animal_scene = load(species["adult"])
			if not animal_scene:
				continue
			var animal = animal_scene.instantiate()
			add_child(animal)
			animal.position = _point_in_room(marker, extents)
			animal.rotation_degrees.y = randf_range(0, 360)

			if pack_spawning and randf() < baby_chance:
				var baby_scene = load(species["young"])
				if baby_scene:
					var baby = baby_scene.instantiate()
					add_child(baby)
					baby.position = _point_in_room(marker, extents)
					baby.rotation_degrees.y = randf_range(0, 360)

func _point_in_room(marker: Marker3D, extents: Vector2) -> Vector3:
	var base = rooms.position + marker.position
	return Vector3(
		base.x + randf_range(-extents.x, extents.x),
		base.y + 0.6,
		base.z + randf_range(-extents.y, extents.y))

func _process(_delta):
	if carcass_quota > 0:
		return  # quota levels show a counter instead of a clock
	var time_left = int(timer.time_left)
	var mins = time_left / 60
	var secs = time_left % 60
	if player and player.has_node("HUD/TimerLabel"):
		player.get_node("HUD/TimerLabel").text = "%d:%02d" % [mins, secs]

func _update_quota_hud() -> void:
	if carcass_quota <= 0 or not player:
		return
	var label = player.get_node_or_null("HUD/TimerLabel")
	if label:
		label.text = "%d / %d" % [carcasses_on_tarp, carcass_quota]

## Called by the tarp's CarcassDropZone every time a body actually lands on the
## canvas. On quota levels this, not the clock, is what ends the level.
func on_carcass_dropped_on_tarp(_carcass: Node) -> void:
	carcasses_on_tarp += 1
	_update_quota_hud()
	if carcass_quota <= 0 or level_ended or carcasses_on_tarp < carcass_quota:
		return
	# Let the last body finish falling before the camera takes over.
	await get_tree().create_timer(1.2).timeout
	_on_timeout()

func _unhandled_input(event):
	# Debug: F10 force-ends the current level immediately, on exactly the path a
	# natural finish takes -- Level1 -> MidCutscene -> Level2, Level2 -> Level3,
	# Level3 -> the ending reveal.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		if level_ended:
			return
		if timer:
			timer.stop()
		if carcass_quota > 0 and carcasses_on_tarp < carcass_quota:
			# Skipping the hunt would leave the tarp bare and the reveal with
			# nothing to reveal, so top it up to quota and let it settle first.
			_debug_fill_tarp(carcass_quota - carcasses_on_tarp)
			await get_tree().create_timer(1.0).timeout
			if level_ended:
				return
		_on_timeout()

## Debug only. Drops stand-in carcasses onto the tarp through the tarp's own
## spawn path, so what F10 produces is the same object the player would have
## carried in -- including the group the ending sequence swaps.
func _debug_fill_tarp(count: int) -> void:
	var zone = get_node_or_null("Tarp/CarcassDropZone")
	if zone == null or not zone.has_method("spawn_tarp_carcass"):
		return
	var species = ["deer_new", "sheep_new", "boar_new",
		"baby_deer_new", "baby_sheep_new", "baby_boar_new"]
	for i in range(count):
		zone.spawn_tarp_carcass(species[i % species.size()], 0.5)

func _on_timeout():
	if level_ended:
		return
	level_ended = true
	var gm = get_node_or_null("/root/GameManager")
	var current_level = gm.level if gm else 1

	if current_level == 1:
		_start_mid_cutscene()
		return

	if current_level >= 3:
		_start_ending_sequence()
		return

	if end_panel:
		end_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if end_text: end_text.text = "The whispers grow louder. The dizzying potion wears off.\n\nTransitioning..."
	var next_scene = "res://scenes/levels/Level3.tscn"

	await get_tree().create_timer(4.0).timeout

	if gm:
		gm.level = 3

	get_tree().change_scene_to_file(next_scene)

func _start_mid_cutscene():
	# The Man in the Suit walks up in-place near the tarp instead of cutting to a
	# separate scene: freeze the player where they stand, snap them to a clean
	# vantage point overlooking the tarp, and let the cutscene play out live.
	if player:
		player.set_frozen(true)
		player.position = _get_tarp_position() + Vector3(0, 1, 2.5)
		player.rotation = Vector3.ZERO
		if player.head:
			player.head.rotation.x = 0

	var mid_scene = load("res://scenes/cutscenes/MidCutscene.tscn")
	if not mid_scene:
		return
	var mid = mid_scene.instantiate()
	add_child(mid)
	mid.cutscene_finished.connect(_on_mid_cutscene_finished)

func _on_mid_cutscene_finished():
	var gm = get_node_or_null("/root/GameManager")
	if gm and "level" in gm:
		gm.level = 2
	get_tree().change_scene_to_file("res://scenes/levels/Level2.tscn")

## The Reveal. Played in this scene, on this tarp, with the bodies the player
## actually carried in -- see scripts/ending_sequence.gd for why it is not a
## separate cutscene scene.
func _start_ending_sequence():
	if timer:
		timer.stop()

	if player:
		player.set_frozen(true)
		var hud = player.get_node_or_null("HUD")
		if hud:
			hud.visible = false
		# Hides the rifle, the flashlight and any shouldered carcass in one go.
		# The ending brings its own camera, so the player's is not needed.
		player.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	# Nothing else moves during the reveal.
	for animal in get_tree().get_nodes_in_group("animals"):
		if animal is Node:
			animal.set_physics_process(false)
			animal.set_process(false)

	var ending_script = load("res://scripts/ending_sequence.gd")
	if ending_script == null:
		push_error("level: ending_sequence.gd missing; falling back to the outro scene")
		get_tree().change_scene_to_file("res://scenes/cutscenes/OutroCutscene.tscn")
		return
	var ending = Node3D.new()
	ending.name = "EndingSequence"
	ending.set_script(ending_script)
	add_child(ending)
	ending.begin(_get_tarp_position())
