extends CanvasLayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	$ColorRect/VBoxContainer/ResumeBtn.pressed.connect(_on_resume)
	$ColorRect/VBoxContainer/MainMenuBtn.pressed.connect(_on_main_menu)
	$ColorRect/VBoxContainer/ExitBtn.pressed.connect(_on_exit)

func _input(event):
	if event.is_action_pressed("ui_cancel") and get_tree().paused:
		_on_resume()

func _on_resume():
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_main_menu():
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_exit():
	get_tree().quit()
