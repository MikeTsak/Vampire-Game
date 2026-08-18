extends Node3D
## One-shot muzzle flash: geometry plus a light that punches and decays.
## Call fire() once per shot; it hides itself again.

## How long the flash is on screen. Short -- a real one is a couple of frames.
@export var flash_time: float = 0.055
## Peak brightness of the burst light.
@export var flash_energy: float = 8.0

var _t: float = 0.0
var _base: Vector3 = Vector3.ONE

@onready var flame: MeshInstance3D = $Flame
@onready var lamp: OmniLight3D = $FlashLight

func _ready() -> void:
	visible = false
	set_process(false)

func fire() -> void:
	# Fresh roll and size every shot, so a string of shots never repeats the
	# same silhouette.
	rotation.z = randf() * TAU
	var s := randf_range(0.85, 1.25)
	_base = Vector3(s, s, s * randf_range(0.9, 1.35))
	flame.scale = _base
	lamp.light_energy = flash_energy
	visible = true
	_t = flash_time
	set_process(true)

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		visible = false
		set_process(false)
		return
	var k: float = _t / flash_time
	# Quadratic falloff on the light, and the flame collapses back toward the
	# bore as it dies.
	lamp.light_energy = flash_energy * k * k
	flame.scale = _base * (0.55 + 0.45 * k)
