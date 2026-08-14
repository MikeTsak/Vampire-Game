extends Node3D

@onready var anim_player = $AnimationPlayer
@onready var fade_rect = $FadeLayer/FadeRect

var transitioning = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta):
	if Input.is_action_just_pressed("ui_accept") and not transitioning:
		skip_cutscene()

func skip_cutscene():
	if transitioning: return
	transitioning = true
	if is_instance_valid(anim_player):
		anim_player.stop()
	_change_scene()

func finish_cutscene():
	if transitioning: return
	transitioning = true
	_change_scene()

func _change_scene():
	get_tree().change_scene_to_file("res://scenes/Level1.tscn")
