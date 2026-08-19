extends CanvasLayer

@onready var master_slider = $CenterContainer/VBoxContainer/MasterVolumeBox/MasterSlider
@onready var music_slider = $CenterContainer/VBoxContainer/MusicVolumeBox/MusicSlider
@onready var sfx_slider = $CenterContainer/VBoxContainer/SFXVolumeBox/SFXSlider
@onready var sensitivity_slider = $CenterContainer/VBoxContainer/SensitivityBox/SensitivitySlider
@onready var brightness_slider = $CenterContainer/VBoxContainer/BrightnessBox/BrightnessSlider
@onready var vintage_filter_check = $CenterContainer/VBoxContainer/VintageFilterBox/VintageFilterCheck
@onready var fps_option = $CenterContainer/VBoxContainer/FPSBox/FPSOption
@onready var fullscreen_check = $CenterContainer/VBoxContainer/FullscreenBox/FullscreenCheck
@onready var back_button = $CenterContainer/VBoxContainer/BackButton

func _ready():
	# Sync UI with SettingsManager
	master_slider.value = SettingsManager.master_volume
	music_slider.value = SettingsManager.music_volume
	sfx_slider.value = SettingsManager.sfx_volume
	sensitivity_slider.value = SettingsManager.mouse_sensitivity
	brightness_slider.value = SettingsManager.brightness
	vintage_filter_check.button_pressed = SettingsManager.vintage_filter_enabled

	if SettingsManager.fps_limit == 30:
		fps_option.selected = 0
	elif SettingsManager.fps_limit == 60:
		fps_option.selected = 1
	else:
		fps_option.selected = 2
		
	fullscreen_check.button_pressed = SettingsManager.fullscreen
	
	# Connect signals
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	brightness_slider.value_changed.connect(_on_brightness_changed)
	vintage_filter_check.toggled.connect(_on_vintage_filter_toggled)
	fps_option.item_selected.connect(_on_fps_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)

func _on_master_changed(value: float):
	SettingsManager.master_volume = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_music_changed(value: float):
	SettingsManager.music_volume = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_sfx_changed(value: float):
	SettingsManager.sfx_volume = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_sensitivity_changed(value: float):
	SettingsManager.mouse_sensitivity = value
	SettingsManager.save_settings()

func _on_brightness_changed(value: float):
	SettingsManager.brightness = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_vintage_filter_toggled(button_pressed: bool):
	SettingsManager.vintage_filter_enabled = button_pressed
	SettingsManager.save_settings()

func _on_fps_selected(index: int):
	if index == 0:
		SettingsManager.fps_limit = 30
	elif index == 1:
		SettingsManager.fps_limit = 60
	else:
		SettingsManager.fps_limit = 0
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_fullscreen_toggled(button_pressed: bool):
	SettingsManager.fullscreen = button_pressed
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_back_pressed():
	queue_free()
