extends Node3D
## The Reveal -- Level 3's ending, played in place on the real tarp.
##
## Nothing is re-staged in a separate scene: the camera cuts to the tarp the
## player has actually been filling, every carcass lying on it is swapped for a
## human body at the exact transform physics left it in, and the world fades to
## THE END. Doing it here rather than in an EndingCutscene.tscn is the whole
## trick -- a hand-placed pile could never match the scatter the player built,
## and matching that scatter is what sells the realisation.

signal finished

const HUMAN_SCENE := "res://scenes/characters/dead_human_new.tscn"

## Beat lengths, in seconds.
const DWELL_ON_ANIMALS := 3.6   ## long enough to read "that is my haul"
const DWELL_ON_HUMANS := 6.0    ## long enough for it to stop being a haul
const FADE_TIME := 2.6
## Sized to finish exactly as the fade starts, so the move never stops dead.
const PUSH_IN_TIME := 10.0

var tarp_position := Vector3.ZERO

var _camera: Camera3D
var _reveal_light: OmniLight3D
var _fade: ColorRect
var _flash: ColorRect
var _title: Label
var _look_at := Vector3.ZERO
var _can_exit := false
var _exited := false


## Entry point. Call this after add_child(), not before -- the camera and the
## overlay are built against the live tree.
func begin(tarp_pos: Vector3) -> void:
	tarp_position = tarp_pos
	_look_at = tarp_position + Vector3(0.0, 0.35, 0.0)
	_build_camera()
	_build_ui()
	_play()


## Stop the pile mid-tumble. The swap reads the resting transform of every
## carcass, so nothing may still be rolling when the humans take their places.
## Called at the moment of the swap, not earlier -- freezing on entry would
## catch anything still falling and leave it hanging in the air.
func _settle_carcasses() -> void:
	for c in get_tree().get_nodes_in_group("tarp_carcass"):
		if c is RigidBody3D:
			c.linear_velocity = Vector3.ZERO
			c.angular_velocity = Vector3.ZERO
			c.freeze = true


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "EndingCamera"
	add_child(_camera)
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.global_position = tarp_position + Vector3(0.0, 2.95, 7.9)
	_camera.look_at(_look_at, Vector3.UP)
	_camera.make_current()

	# A slow, unbroken push-in. No cuts: the player is not allowed to look away.
	var push := create_tween()
	push.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	push.tween_property(_camera, "global_position",
		tarp_position + Vector3(0.0, 2.0, 4.8), PUSH_IN_TIME)

	# The oil lamp alone leaves the pile half-read. This lifts it out of the
	# dark over the first couple of seconds so the swap has something to land on.
	_reveal_light = OmniLight3D.new()
	_reveal_light.name = "RevealLight"
	add_child(_reveal_light)
	_reveal_light.global_position = tarp_position + Vector3(0.0, 2.9, 1.6)
	_reveal_light.light_color = Color(1.0, 0.84, 0.64)
	_reveal_light.light_energy = 0.0
	_reveal_light.omni_range = 16.0
	var lift := create_tween()
	lift.tween_property(_reveal_light, "light_energy", 4.2, 2.4)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "EndingUI"
	layer.layer = 30
	add_child(layer)

	_flash = ColorRect.new()
	_flash.name = "FlashRect"
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.9, 0.86, 0.88)
	_flash.modulate.a = 0.0
	_flash.visible = false
	layer.add_child(_flash)

	_fade = ColorRect.new()
	_fade.name = "FadeRect"
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	layer.add_child(_fade)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "Consolas", "Monospace"])

	_title = Label.new()
	_title.name = "TheEnd"
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.text = "THE END"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", font)
	_title.add_theme_font_size_override("font_size", 92)
	_title.add_theme_color_override("font_color", Color(0.86, 0.86, 0.84))
	_title.modulate.a = 0.0
	_title.visible = false
	layer.add_child(_title)


func _process(_delta: float) -> void:
	# Re-aim every frame so the push-in keeps the pile dead centre instead of
	# drifting off the bottom of the frame as the camera drops.
	if is_instance_valid(_camera):
		_camera.look_at(_look_at, Vector3.UP)


func _play() -> void:
	await get_tree().create_timer(DWELL_ON_ANIMALS).timeout
	_glitch_flash()
	await get_tree().create_timer(0.42).timeout
	_swap_to_humans()
	await get_tree().create_timer(DWELL_ON_HUMANS).timeout
	await _fade_to_black()
	await _show_title()
	_can_exit = true


func _glitch_flash() -> void:
	if _flash:
		_flash.visible = true
		var t := create_tween()
		t.tween_property(_flash, "modulate:a", 0.85, 0.03)
		t.tween_property(_flash, "modulate:a", 0.0, 0.06)
		t.tween_property(_flash, "modulate:a", 0.7, 0.03)
		t.tween_property(_flash, "modulate:a", 0.0, 0.14)
	if is_instance_valid(_camera):
		# Shake through the lens offsets, not the transform -- the push-in tween
		# owns global_position and two tweens on one property fight each other.
		var c := create_tween()
		c.tween_property(_camera, "h_offset", 0.06, 0.03)
		c.tween_property(_camera, "v_offset", -0.05, 0.03)
		c.tween_property(_camera, "h_offset", -0.05, 0.03)
		c.tween_property(_camera, "v_offset", 0.0, 0.04)
		c.tween_property(_camera, "h_offset", 0.0, 0.04)


## Every animal on the tarp becomes a person, standing exactly where the animal
## lay. Only the group the tarp itself fills is touched -- carcasses still out
## in the rooms are left alone.
func _swap_to_humans() -> void:
	var human_scene: PackedScene = load(HUMAN_SCENE)
	if human_scene == null:
		push_error("ending_sequence: could not load %s" % HUMAN_SCENE)
		return
	_settle_carcasses()
	var tarp_top := tarp_position.y + 0.06
	for carcass in get_tree().get_nodes_in_group("tarp_carcass"):
		if not is_instance_valid(carcass) or not (carcass is Node3D):
			continue
		var xf: Transform3D = carcass.global_transform
		var human: Node3D = human_scene.instantiate()
		add_child(human)
		# Same footprint, same angle: keep the spot on the canvas and the yaw the
		# body happened to settle at, and just lay the corpse down flat on it.
		human.global_position = Vector3(xf.origin.x, tarp_top, xf.origin.z)
		human.rotation = Vector3(0.0, xf.basis.get_euler().y, 0.0)
		carcass.queue_free()


func _fade_to_black() -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await t.finished
	# Nothing left to look at; drop the 3D so the black is genuinely black.
	if is_instance_valid(_reveal_light):
		_reveal_light.light_energy = 0.0


func _show_title() -> void:
	await get_tree().create_timer(1.0).timeout
	_title.visible = true
	var t := create_tween()
	t.tween_property(_title, "modulate:a", 1.0, 1.6)
	await t.finished


func _unhandled_input(event: InputEvent) -> void:
	if not _can_exit or _exited:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_exited = true
		finished.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
