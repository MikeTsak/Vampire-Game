extends OmniLight3D
## A fixture that is most of the way to dead.
##
## The trick is the gap: it holds steady long enough that you stop watching it,
## then stutters for a fraction of a second. A light that flickers constantly
## becomes wallpaper -- this one keeps catching the eye.

## Longest and shortest quiet stretch between fits, in seconds.
@export var min_gap: float = 2.0
@export var max_gap: float = 9.0
## How long a fit lasts once it starts.
@export var min_burst: float = 0.12
@export var max_burst: float = 0.65
## Chance the fixture is simply dead for a whole cycle instead of stuttering.
@export var dropout_chance: float = 0.25

var _base_energy: float = 1.0
var _quiet: float = 0.0
var _burst: float = 0.0
var _dropped: bool = false


func _ready() -> void:
	_base_energy = light_energy
	# Stagger them, or every fixture in the building fires on the same frame.
	_quiet = randf_range(0.0, max_gap)


func _process(delta: float) -> void:
	if _burst > 0.0:
		_burst -= delta
		if _dropped:
			light_energy = 0.0
		else:
			light_energy = _base_energy * (0.04 if randf() < 0.5 else randf_range(0.55, 1.4))
		if _burst <= 0.0:
			light_energy = _base_energy
		return

	_quiet -= delta
	if _quiet <= 0.0:
		_quiet = randf_range(min_gap, max_gap)
		_burst = randf_range(min_burst, max_burst)
		_dropped = randf() < dropout_chance
		if _dropped:
			# A dropout reads as the fixture giving up, so let it stay out longer.
			_burst *= 2.5
