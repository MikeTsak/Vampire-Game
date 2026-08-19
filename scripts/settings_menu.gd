extends CanvasLayer

@onready var master_slider = $CenterContainer/VBoxContainer/MasterVolumeBox/MasterSlider
@onready var sfx_slider = $CenterContainer/VBoxContainer/SFXVolumeBox/SFXSlider
@onready var sensitivity_slider = $CenterContainer/VBoxContainer/SensitivityBox/SensitivitySlider
@onready var gamepad_slider = $CenterContainer/VBoxContainer/GamepadBox/GamepadSlider
@onready var pixelation_slider = $CenterContainer/VBoxContainer/PixelationBox/PixelationSlider
@onready var brightness_slider = $CenterContainer/VBoxContainer/BrightnessBox/BrightnessSlider
@onready var fps_option = $CenterContainer/VBoxContainer/FPSBox/FPSOption
@onready var fullscreen_check = $CenterContainer/VBoxContainer/FullscreenBox/FullscreenCheck
@onready var back_button = $CenterContainer/VBoxContainer/BackButton

func _ready():
	# Sync UI with SettingsManager
	master_slider.value = SettingsManager.master_volume
	sfx_slider.value = SettingsManager.sfx_volume
	sensitivity_slider.value = SettingsManager.mouse_sensitivity
	gamepad_slider.value = SettingsManager.controller_sensitivity
	pixelation_slider.value = SettingsManager.pixelation
	brightness_slider.value = SettingsManager.brightness
	
	if SettingsManager.fps_limit == 30:
		fps_option.selected = 0
	elif SettingsManager.fps_limit == 60:
		fps_option.selected = 1
	else:
		fps_option.selected = 2
		
	fullscreen_check.button_pressed = SettingsManager.fullscreen
	
	# Connect signals
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	gamepad_slider.value_changed.connect(_on_gamepad_changed)
	pixelation_slider.value_changed.connect(_on_pixelation_changed)
	brightness_slider.value_changed.connect(_on_brightness_changed)
	fps_option.item_selected.connect(_on_fps_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)
	
	master_slider.grab_focus()

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _on_master_changed(value: float):
	SettingsManager.master_volume = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_sfx_changed(value: float):
	SettingsManager.sfx_volume = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_sensitivity_changed(value: float):
	SettingsManager.mouse_sensitivity = value
	SettingsManager.save_settings()

func _on_gamepad_changed(value: float):
	SettingsManager.controller_sensitivity = value
	SettingsManager.save_settings()

func _on_pixelation_changed(value: float):
	SettingsManager.pixelation = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_brightness_changed(value: float):
	SettingsManager.brightness = value
	SettingsManager.apply_settings()
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
