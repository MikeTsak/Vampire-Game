extends SpotLight3D

var noise = FastNoiseLite.new()
var time_passed := 0.0
var base_energy := 0.0

func _ready():
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 5.0
	base_energy = light_energy

func _process(delta):
	time_passed += delta
	# Simulate a dying/flickering battery
	var flicker = noise.get_noise_1d(time_passed * 10.0)
	
	if flicker > 0.5:
		# Sharp drop in energy
		light_energy = base_energy * randf_range(0.2, 0.6)
	else:
		# Normal slight wobble
		light_energy = base_energy * (1.0 + flicker * 0.1)
