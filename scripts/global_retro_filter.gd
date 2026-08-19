extends CanvasLayer

func _process(delta):
	var tree = get_tree()
	if not tree or not tree.current_scene: return
	var on_menu_scene = tree.current_scene.name == "MainMenu" or tree.current_scene.name == "Credits"
	var settings = get_node_or_null("/root/SettingsManager")
	var filter_enabled = settings == null or settings.vintage_filter_enabled
	$ColorRect.visible = not on_menu_scene and filter_enabled
