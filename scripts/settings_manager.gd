extends Node

const CONFIG_PATH = "user://settings.cfg"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var mouse_sensitivity: float = 1.0
var fullscreen: bool = false
var pixelation: float = 1.0
var fps_limit: int = 60
var brightness: float = 1.0
var controller_sensitivity: float = 2.0

var brightness_overlay: ColorRect

func _ready():
	var vp = get_viewport()
	vp.use_taa = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.msaa_2d = Viewport.MSAA_DISABLED
	
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	brightness_overlay = ColorRect.new()
	brightness_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	brightness_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(brightness_overlay)
	add_child(canvas)
	
	_setup_controller_inputs()
	load_settings()

func load_settings():
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	
	if err == OK:
		master_volume = config.get_value("Audio", "master_volume", 1.0)
		sfx_volume = config.get_value("Audio", "sfx_volume", 1.0)
		mouse_sensitivity = config.get_value("Gameplay", "mouse_sensitivity", 1.0)
		fullscreen = config.get_value("Graphics", "fullscreen", false)
		pixelation = config.get_value("Graphics", "pixelation", 1.0)
		fps_limit = config.get_value("Graphics", "fps_limit", 60)
		brightness = config.get_value("Graphics", "brightness", 1.0)
		controller_sensitivity = config.get_value("Gameplay", "controller_sensitivity", 2.0)
	
	apply_settings()

func save_settings():
	var config = ConfigFile.new()
	config.set_value("Audio", "master_volume", master_volume)
	config.set_value("Audio", "sfx_volume", sfx_volume)
	config.set_value("Gameplay", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("Gameplay", "controller_sensitivity", controller_sensitivity)
	config.set_value("Graphics", "fullscreen", fullscreen)
	config.set_value("Graphics", "pixelation", pixelation)
	config.set_value("Graphics", "fps_limit", fps_limit)
	config.set_value("Graphics", "brightness", brightness)
	config.save(CONFIG_PATH)

func apply_settings():
	# Apply Master volume (Bus 0)
	var master_bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(master_volume))
	
	# Apply SFX volume (PS1_Retro bus)
	var sfx_bus = AudioServer.get_bus_index("PS1_Retro")
	if sfx_bus != -1:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(sfx_volume))
		
	# Fullscreen
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# Pixelation
	get_viewport().scaling_3d_scale = pixelation
	
	# FPS Limit
	Engine.max_fps = fps_limit
	
	# Brightness (0.0 to 2.0 range)
	if brightness <= 1.0:
		# Darken
		brightness_overlay.color = Color(0, 0, 0, 1.0 - brightness)
	else:
		# Brighten
		brightness_overlay.color = Color(1, 1, 1, (brightness - 1.0) * 0.5)

func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

func db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)

func _setup_controller_inputs():
	_add_joy_axis("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("ui_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
	_add_joy_button("shoot", JOY_BUTTON_RIGHT_SHOULDER)
	_add_mouse_button("shoot", MOUSE_BUTTON_LEFT)
	
	_add_joy_button("interact", JOY_BUTTON_A)
	_add_joy_button("ui_accept", JOY_BUTTON_A)
	_add_joy_button("ui_cancel", JOY_BUTTON_START)
	_add_joy_button("ui_cancel", JOY_BUTTON_B)

func _add_joy_axis(action: String, axis: int, direction: float):
	if not InputMap.has_action(action): InputMap.add_action(action)
	var ev = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)

func _add_joy_button(action: String, button: int):
	if not InputMap.has_action(action): InputMap.add_action(action)
	var ev = InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _add_mouse_button(action: String, button: int):
	if not InputMap.has_action(action): InputMap.add_action(action)
	var ev = InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
