extends Control

func _ready():
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)

	# Level shortcuts for testing. Built in code rather than authored into the
	# .tscn so the menu's branding layout stays exactly as designed, and kept
	# side by side on a single row -- the menu column is sized so that a sixth
	# row would run into the footer credits.
	var lvl2 := _ensure_debug_button("DebugLevel2Button", "Debug Level 2")
	lvl2.pressed.connect(_on_debug_level2_pressed)
	var lvl3 := _ensure_debug_button("DebugLevel3Button", "Debug Level 3")
	lvl3.pressed.connect(_on_debug_level3_pressed)

	$VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$VBoxContainer/ModelViewerButton.pressed.connect(_on_model_viewer_pressed)
	$VBoxContainer/ExitButton.pressed.connect(_on_exit_pressed)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## The single row both debug shortcuts sit on, created under Play on first use.
func _debug_row() -> HBoxContainer:
	var row = $VBoxContainer.get_node_or_null("DebugRow")
	if row:
		return row
	row = HBoxContainer.new()
	row.name = "DebugRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	$VBoxContainer.add_child(row)
	$VBoxContainer.move_child(row, 1)
	return row

## Returns the named debug button, creating it on the debug row if it is not
## there yet. New buttons copy the authored menu styling -- left to the default
## theme they land in the middle of the menu looking nothing like neighbours.
func _ensure_debug_button(node_name: String, label: String) -> Button:
	var row := _debug_row()
	var existing = row.get_node_or_null(node_name)
	if existing:
		return existing

	var btn := Button.new()
	btn.name = node_name
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sibling: Button = $VBoxContainer/PlayButton
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 16)
	for key in ["font_color", "font_hover_color", "font_focus_color"]:
		btn.add_theme_color_override(key, sibling.get_theme_color(key))
	var f := sibling.get_theme_font("font")
	if f:
		btn.add_theme_font_override("font", f)
	row.add_child(btn)
	return btn

func _on_play_pressed():
	get_tree().change_scene_to_file("res://scenes/cutscenes/IntroCutscene.tscn")

func _on_debug_level2_pressed():
	_go_to_level(2)

func _on_debug_level3_pressed():
	_go_to_level(3)

## Levels set GameManager.level from their own level_number on load, but the
## skinwalker and the pack spawner read it during that same frame, so hand it
## over before the scene change rather than after.
func _go_to_level(level: int):
	var gm = get_node_or_null("/root/GameManager")
	if gm and "level" in gm:
		gm.level = level
	get_tree().change_scene_to_file("res://scenes/levels/Level%d.tscn" % level)

func _on_settings_pressed():
	print("Settings clicked")

func _on_model_viewer_pressed():
	get_tree().change_scene_to_file("res://scenes/dev/ModelViewer.tscn")

func _on_exit_pressed():
	get_tree().quit()
