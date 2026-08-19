extends Camera3D

var base_rotation: Vector3
var time_passed: float = 0.0

func _ready():
	look_at(Vector3(0, 5, -40))
	base_rotation = rotation

func _process(delta):
	time_passed += delta
	# Slow, eerie sway on the Y axis
	rotation.y = base_rotation.y + sin(time_passed * 0.2) * 0.05
	# Tiny sway on X axis
	rotation.x = base_rotation.x + cos(time_passed * 0.15) * 0.02
