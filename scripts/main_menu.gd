extends Control

func _ready():
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	var debug_btn = $VBoxContainer.get_node_or_null("DebugLevel2Button")
	if not debug_btn:
		debug_btn = Button.new()
		debug_btn.name = "DebugLevel2Button"
		debug_btn.text = "Debug Level 2"
		# Match the authored buttons, otherwise this one lands in the middle of
		# the menu in the default theme and breaks the branding.
		var sibling: Button = $VBoxContainer/PlayButton
		debug_btn.flat = true
		debug_btn.add_theme_font_size_override("font_size", 20)
		for key in ["font_color", "font_hover_color", "font_focus_color"]:
			debug_btn.add_theme_color_override(key, sibling.get_theme_color(key))
		var f := sibling.get_theme_font("font")
		if f:
			debug_btn.add_theme_font_override("font", f)
		$VBoxContainer.add_child(debug_btn)
		$VBoxContainer.move_child(debug_btn, 1)
	debug_btn.pressed.connect(_on_debug_level2_pressed)
	$VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$VBoxContainer/ModelViewerButton.pressed.connect(_on_model_viewer_pressed)
	$VBoxContainer/ExitButton.pressed.connect(_on_exit_pressed)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_play_pressed():
	get_tree().change_scene_to_file("res://scenes/cutscenes/IntroCutscene.tscn")

func _on_debug_level2_pressed():
	get_tree().change_scene_to_file("res://scenes/levels/Level2.tscn")

func _on_settings_pressed():
	print("Settings clicked")

func _on_model_viewer_pressed():
	get_tree().change_scene_to_file("res://scenes/dev/ModelViewer.tscn")

func _on_exit_pressed():
	get_tree().quit()
