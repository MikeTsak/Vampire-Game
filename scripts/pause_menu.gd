extends CanvasLayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	$ColorRect/VBoxContainer/ResumeBtn.pressed.connect(_on_resume)
	$ColorRect/VBoxContainer/MainMenuBtn.pressed.connect(_on_main_menu)
	$ColorRect/VBoxContainer/ExitBtn.pressed.connect(_on_exit)

func _on_resume():
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.toggle_pause()

func _on_main_menu():
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		if get_tree().paused:
			gm.toggle_pause() # Unpause before leaving
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_exit():
	get_tree().quit()
