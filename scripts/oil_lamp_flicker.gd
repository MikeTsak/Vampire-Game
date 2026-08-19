extends OmniLight3D
## A guttering oil flame -- layered sine waves keep it restless, but unlike a
## dying electric fixture it never drops fully dark. See lamp_flicker.gd for
## the harsher stutter-and-dropout style used on the sanatorium's wiring.

@export var flicker_speed: float = 5.5
@export var flicker_speed_fast: float = 13.0
@export var flicker_amount: float = 0.3
@export var jitter_amount: float = 0.12
@export var range_flutter: float = 0.06

var _base_energy: float = 1.0
var _base_range: float = 1.0
var _seed: float = 0.0

func _ready() -> void:
	_base_energy = light_energy
	_base_range = omni_range
	_seed = randf_range(0.0, TAU)

func _process(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0 + _seed
	var wave: float = sin(t * flicker_speed) * 0.65 + sin(t * flicker_speed_fast + 1.7) * 0.35
	var jitter: float = (randf() - 0.5) * jitter_amount
	var factor: float = clamp(1.0 + wave * flicker_amount + jitter, 0.45, 1.5)
	light_energy = _base_energy * factor
	omni_range = _base_range * (1.0 - range_flutter * 0.5 + wave * range_flutter * 0.5)
