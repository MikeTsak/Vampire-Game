extends Control
## Loads the real main menu and grabs a frame, so the rebrand can be reviewed
## without opening the editor.

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1152, 648))
	add_child(load("res://ui/MainMenu.tscn").instantiate())
	call_deferred("_run")

func _run() -> void:
	var dir := OS.get_environment("MENU_SHOT_DIR")
	if dir == "":
		dir = "res://"
	elif not dir.ends_with("/"):
		dir += "/"
	for i in 20:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("menu shot err=%d" % img.save_png(dir + "menu.png"))
	get_tree().quit()
