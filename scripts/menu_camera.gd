extends Camera3D

@export var sway_speed: float = 0.5
@export var sway_amount: float = 0.5

var initial_rotation: Vector3
var time: float = 0.0

func _ready():
	initial_rotation = rotation

func _process(delta):
	time += delta * sway_speed
	var sway_x = sin(time) * sway_amount * 0.02
	var sway_y = cos(time * 0.8) * sway_amount * 0.02
	
	rotation.x = initial_rotation.x + sway_x
	rotation.y = initial_rotation.y + sway_y
