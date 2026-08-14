extends Camera3D

func _process(_delta):
	var main_cam = get_viewport().get_camera_3d()
	if main_cam and main_cam != self:
		global_transform.basis = main_cam.global_transform.basis
		fov = main_cam.fov
