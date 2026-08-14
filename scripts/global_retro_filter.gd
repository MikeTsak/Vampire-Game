extends CanvasLayer

func _process(delta):
	var tree = get_tree()
	if not tree or not tree.current_scene: return
	if tree.current_scene.name == "MainMenu" or tree.current_scene.name == "Credits":
		$ColorRect.visible = false
	else:
		$ColorRect.visible = true
