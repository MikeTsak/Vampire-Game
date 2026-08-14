extends Node3D

@onready var anim_player = $AnimationPlayer
@onready var fade_rect = $FadeLayer/FadeRect

var transitioning = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta):
	if Input.is_action_just_pressed("ui_select") and not transitioning:
		skip_cutscene()

func skip_cutscene():
	if transitioning: return
	transitioning = true
	anim_player.stop()
	var tween = get_tree().create_tween()
	tween.tween_property(fade_rect, "color", Color(0, 0, 0, 1), 0.5)
	tween.tween_callback(self._change_scene)

func finish_cutscene():
	if transitioning: return
	transitioning = true
	# Assuming fade is handled by the animation player at the end
	_change_scene()

func _change_scene():
	get_tree().change_scene_to_file("res://scenes/Level1.tscn")
