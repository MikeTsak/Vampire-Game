extends SpotLight3D
## A tired battery in an old trench light -- a faint, continuous unsteadiness.
## Stays above min_factor always, so the beam never leaves the player blind.

@export var flicker_speed: float = 23.0
@export var flicker_speed_fast: float = 61.0
@export var flicker_amount: float = 0.05
@export var min_factor: float = 0.85

var _base_energy: float = 1.0
var _seed: float = 0.0

func _ready() -> void:
	_base_energy = light_energy
	_seed = randf_range(0.0, TAU)

func _process(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0 + _seed
	var wave: float = sin(t * flicker_speed) + sin(t * flicker_speed_fast) * 0.4
	var factor: float = 1.0 + wave * flicker_amount * 0.3
	light_energy = _base_energy * max(factor, min_factor)
