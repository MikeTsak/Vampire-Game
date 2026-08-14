extends CSGCylinder3D

var last_pos = Vector3()
var tilt = Vector3()
var wobble_factor = 1.0
var recovery_speed = 8.0
var max_tilt = 0.3

func _ready():
	last_pos = global_position

func _process(delta):
	if delta == 0: return
	
	var current_pos = global_position
	# Compute global velocity
	var velocity = (current_pos - last_pos) / delta
	last_pos = current_pos
	
	# Convert global velocity to local velocity to tilt correctly
	var local_vel = global_transform.basis.inverse() * velocity
	
	# Add tilt based on local acceleration/velocity (simplification)
	var target_tilt = Vector3(local_vel.z, 0, -local_vel.x) * wobble_factor * delta
	target_tilt.x = clamp(target_tilt.x, -max_tilt, max_tilt)
	target_tilt.z = clamp(target_tilt.z, -max_tilt, max_tilt)
	
	tilt += target_tilt
	tilt = tilt.lerp(Vector3.ZERO, delta * recovery_speed)
	
	rotation = tilt
