extends SpotLight3D
# Ultra-Powerful WWI Trench Flashlight Controller
# Built to pierce straight through screen filters and absolute darkness.

@export var base_energy: float = 10.0
@export var max_range: float = 35.0
@export var spot_beam_angle: float = 35.0
@export var flicker_intensity: float = 0.5
@export var flicker_speed: float = 14.0

var noise := FastNoiseLite.new()
var time_passed: float = 0.0

func _ready() -> void:
	# Position strictly in front of the camera and barrel to completely eliminate weapon shadows
	transform.origin = Vector3(-0.25, -0.1, -1.8)
	
	# Massive power settings to bypass post-processing/filters
	light_energy = base_energy
	spot_range = max_range
	spot_angle = spot_beam_angle
	spot_attenuation = 2.0 # Higher attenuation so it fades into darkness naturally
	shadow_enabled = true
	
	# Point slightly upwards
	rotation_degrees.x = 1.0
	
	# Warm WWI vintage bulb tint
	light_color = Color(1.0, 0.82, 0.55)
	
	# Initialize noise for organic vacuum-tube bulb flicker
	noise.seed = randi()
	noise.frequency = 3.0

func _process(delta: float) -> void:
	time_passed += delta * flicker_speed
	var flicker = noise.get_noise_1d(time_passed) * flicker_intensity
	# Keep brightness high but not blinding
	light_energy = max(5.0, base_energy + flicker)
