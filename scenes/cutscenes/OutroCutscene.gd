extends Node3D

@onready var subtitle_label = $Subtitles/SubtitleLabel
@onready var fade_rect = $Subtitles/FadeRect
@onready var flash_rect = $Subtitles/FlashRect
@onready var camera = $Camera3D
@onready var pile_root = $CarcassPile

var transitioning = false
var skipping = false
var revealed = false

const ANIMAL_SCENES = [
	"res://scenes/animals/deer_new.tscn",
	"res://scenes/animals/sheep_new.tscn",
	"res://scenes/animals/baby_sheep_new.tscn",
	"res://scenes/animals/baby_deer_new.tscn",
	"res://scenes/animals/boar_new.tscn",
]
const HUMAN_SCENES = [
	"res://scenes/characters/dead_man_new.tscn",
	"res://scenes/characters/dead_woman_new.tscn",
	"res://scenes/characters/dead_boy_new.tscn",
	"res://scenes/characters/dead_girl_new.tscn",
	"res://scenes/characters/dead_human_new.tscn",
]

var pile_slots = []

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spawn_pile()
	_run_sequence()

func _spawn_pile():
	var positions = [
		Vector3(-1.2, 0.05, -0.8), Vector3(0.6, 0.05, -1.0), Vector3(0.0, 0.05, 0.2),
		Vector3(-0.7, 0.05, 0.9), Vector3(1.1, 0.05, 0.6),
	]
	for i in range(positions.size()):
		var scene = load(ANIMAL_SCENES[i % ANIMAL_SCENES.size()])
		if not scene:
			continue
		var inst = scene.instantiate()
		inst.set_script(null)
		inst.process_mode = Node.PROCESS_MODE_DISABLED
		pile_root.add_child(inst)
		inst.position = positions[i]
		inst.rotation = Vector3(PI, randf_range(0, TAU), PI / 2)
		pile_slots.append({"node": inst, "pos": positions[i]})

func _unhandled_input(event):
	if transitioning:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_select") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		skipping = true
		if not revealed:
			_reveal_humans()
		_end_game()

func _run_sequence():
	if subtitle_label:
		subtitle_label.text = ""
	await get_tree().create_timer(2.0).timeout
	if skipping: return

	if await _say("It's done. A good haul.", 3.0): return
	if skipping: return

	await get_tree().create_timer(1.0).timeout
	if skipping: return

	_glitch_flash()
	await get_tree().create_timer(0.5).timeout
	if skipping: return
	_reveal_humans()
	await get_tree().create_timer(0.9).timeout
	if skipping: return

	if await _say("...that's not meat.", 3.0): return
	if skipping: return

	if await _say("What have I been carrying down this mountain?", 4.0): return
	if skipping: return

	_end_game()

func _say(text: String, duration: float) -> bool:
	if subtitle_label:
		subtitle_label.text = text
	await get_tree().create_timer(duration).timeout
	if subtitle_label:
		subtitle_label.text = ""
	if skipping:
		return true
	await get_tree().create_timer(0.4).timeout
	return skipping

func _glitch_flash():
	if flash_rect:
		flash_rect.visible = true
		var t = create_tween()
		t.tween_property(flash_rect, "modulate:a", 0.9, 0.03)
		t.tween_property(flash_rect, "modulate:a", 0.0, 0.05)
		t.tween_property(flash_rect, "modulate:a", 0.8, 0.03)
		t.tween_property(flash_rect, "modulate:a", 0.0, 0.12)
	if camera:
		var base_pos = camera.position
		var cam_t = create_tween()
		cam_t.tween_property(camera, "position", base_pos + Vector3(0.05, -0.03, 0), 0.03)
		cam_t.tween_property(camera, "position", base_pos + Vector3(-0.04, 0.04, 0), 0.03)
		cam_t.tween_property(camera, "position", base_pos, 0.05)

func _reveal_humans():
	if revealed:
		return
	revealed = true
	for i in range(pile_slots.size()):
		var slot = pile_slots[i]
		var human_scene = load(HUMAN_SCENES[i % HUMAN_SCENES.size()])
		if not human_scene:
			continue
		var old = slot["node"]
		var human = human_scene.instantiate()
		pile_root.add_child(human)
		human.position = slot["pos"]
		human.rotation = Vector3(0, randf_range(0, TAU), 0)
		if is_instance_valid(old):
			old.queue_free()

func _end_game():
	if transitioning:
		return
	transitioning = true
	if fade_rect:
		fade_rect.visible = true
		var tween = create_tween()
		tween.tween_property(fade_rect, "modulate:a", 1.0, 1.2)
		await tween.finished
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
