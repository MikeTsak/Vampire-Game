extends MeshInstance3D

func _process(_delta):
	var camera = get_viewport().get_camera_3d()
	if camera:
		global_position = camera.global_position
