extends Node

@onready var play_button = $UILayer/Control/VBoxContainer/PlayButton
@onready var settings_button = $UILayer/Control/VBoxContainer/SettingsButton
@onready var model_viewer_button = $UILayer/Control/VBoxContainer/ModelViewerButton
@onready var exit_button = $UILayer/Control/VBoxContainer/ExitButton
@onready var level2_button = $UILayer/Control/VBoxContainer/DebugRow/Level2Btn
@onready var level3_button = $UILayer/Control/VBoxContainer/DebugRow/Level3Btn

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	if model_viewer_button: model_viewer_button.pressed.connect(_on_model_viewer_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	if level2_button: level2_button.pressed.connect(_on_level2_pressed)
	if level3_button: level3_button.pressed.connect(_on_level3_pressed)
	
	play_button.grab_focus()

func _on_play_pressed():
	get_tree().change_scene_to_file("res://scenes/cutscenes/IntroCutscene.tscn")

func _on_settings_pressed():
	var settings = load("res://ui/SettingsMenu.tscn").instantiate()
	add_child(settings)

func _on_model_viewer_pressed():
	get_tree().change_scene_to_file("res://scenes/dev/ModelViewer.tscn")

func _on_exit_pressed():
	get_tree().quit()

func _on_level2_pressed():
	get_tree().change_scene_to_file("res://scenes/levels/Level2.tscn")

func _on_level3_pressed():
	get_tree().change_scene_to_file("res://scenes/levels/Level3.tscn")
