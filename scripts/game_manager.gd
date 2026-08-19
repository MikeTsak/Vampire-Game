extends Node
# Force recompile
var drachmas: int = 0
var level: int = 1

func add_score(amount: int):
	drachmas += amount

func reset_score():
	drachmas = 0

func next_level():
	level += 1
	var scene_path = "res://scenes/levels/Level%d.tscn" % level
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		# End of game
		pass

var pause_menu: CanvasLayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()

func toggle_pause():
	if not pause_menu:
		var scene = load("res://ui/PauseMenu.tscn")
		if scene:
			pause_menu = scene.instantiate()
			add_child(pause_menu)
	
	if get_tree().paused:
		get_tree().paused = false
		if pause_menu:
			pause_menu.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		get_tree().paused = true
		if pause_menu:
			pause_menu.visible = true
			var resume_btn = pause_menu.get_node_or_null("ColorRect/VBoxContainer/ResumeBtn")
			if resume_btn:
				resume_btn.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
