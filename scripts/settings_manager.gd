extends Node

const CONFIG_PATH = "user://settings.cfg"

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var mouse_sensitivity: float = 1.0
var fullscreen: bool = false
var fps_limit: int = 0
var brightness: float = 1.0
var vintage_filter_enabled: bool = true

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
	
	load_settings()

func load_settings():
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	
	if err == OK:
		master_volume = config.get_value("Audio", "master_volume", 1.0)
		music_volume = config.get_value("Audio", "music_volume", 1.0)
		sfx_volume = config.get_value("Audio", "sfx_volume", 1.0)
		mouse_sensitivity = config.get_value("Gameplay", "mouse_sensitivity", 1.0)
		fullscreen = config.get_value("Graphics", "fullscreen", false)
		fps_limit = config.get_value("Graphics", "fps_limit", 0)
		brightness = config.get_value("Graphics", "brightness", 1.0)
		vintage_filter_enabled = config.get_value("Graphics", "vintage_filter_enabled", true)
	
	apply_settings()

func save_settings():
	var config = ConfigFile.new()
	config.set_value("Audio", "master_volume", master_volume)
	config.set_value("Audio", "music_volume", music_volume)
	config.set_value("Audio", "sfx_volume", sfx_volume)
	config.set_value("Gameplay", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("Graphics", "fullscreen", fullscreen)
	config.set_value("Graphics", "fps_limit", fps_limit)
	config.set_value("Graphics", "brightness", brightness)
	config.set_value("Graphics", "vintage_filter_enabled", vintage_filter_enabled)
	config.save(CONFIG_PATH)

func apply_settings():
	# Apply Master volume (Bus 0)
	var master_bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(master_volume))
	
	# Apply Music volume (Music bus)
	var music_bus = AudioServer.get_bus_index("Music")
	if music_bus != -1:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(music_volume))
	
	# Apply SFX volume (SFX bus)
	var sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus != -1:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(sfx_volume))
		
	# Fullscreen
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

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
