extends Node3D
## Turnaround renderer for the Skinwalker preview stage.
##
## The editor caches .res/.tres between builds, so editor screenshots go stale
## the moment the generator reruns. Launching this scene as a game guarantees
## every resource is read fresh off disk. It spins the turntable, saves one PNG
## per angle into $SW_SHOT_DIR, and quits.

const ANGLES := [180.0, 145.0, 90.0, 35.0, 0.0]

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(768, 768))
	call_deferred("_run")

## Optional framing overrides, so a detail pass can get in close without
## editing the generated scene: SW_TARGET="x,y,z", SW_DIST, SW_FOV.
func _reframe() -> void:
	var tgt := OS.get_environment("SW_TARGET")
	if tgt != "":
		var parts := tgt.split(",")
		if parts.size() == 3:
			$Turntable.position = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var dist := OS.get_environment("SW_DIST")
	if dist != "":
		$Turntable/Camera3D.position = Vector3(0, 0, float(dist))
		$Turntable/Camera3D.rotation = Vector3.ZERO
	var fov := OS.get_environment("SW_FOV")
	if fov != "":
		$Turntable/Camera3D.fov = float(fov)

func _run() -> void:
	_reframe()
	# SW_NOCULL=1 renders both faces: if a "hollow / inside-out" look vanishes
	# under it the cause is winding, if it survives it is a real gap in the mesh.
	# SW_DARK=1 drops the stage to night levels. The eye glow has to be judged
	# in the lighting it actually ships in -- a bright studio makes any emissive
	# read as a garish flood.
	if OS.get_environment("SW_DARK") == "1":
		var env: Environment = $WorldEnvironment.environment
		env.background_color = Color(0.03, 0.035, 0.05)
		env.ambient_light_color = Color(0.10, 0.12, 0.18)
		env.ambient_light_energy = 0.30
		$KeyLight.light_energy = 0.16
		$KeyLight.light_color = Color(0.55, 0.62, 0.85)
		$FillLight.light_energy = 0.05
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(14, 14)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.24, 0.22, 0.20)
		gm.roughness = 1.0
		ground.material_override = gm
		add_child(ground)
	# SW_EYE="energy,range" overrides the eye lamps, for sweeping the glow
	# without a rebuild between each try.
	var eye := OS.get_environment("SW_EYE")
	if eye != "":
		var ev := eye.split(",")
		for lamp in $Skinwalker/MeshBase/Skeleton3D/HeadAttach.get_children():
			lamp.light_energy = float(ev[0])
			if ev.size() > 1:
				lamp.omni_range = float(ev[1])
	if OS.get_environment("SW_NOCULL") == "1":
		var mi: MeshInstance3D = $Skinwalker/MeshBase/Skeleton3D/SkinwalkerLOD0
		var m: StandardMaterial3D = mi.mesh.surface_get_material(0).duplicate()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.set_surface_override_material(0, m)
	var dir := OS.get_environment("SW_SHOT_DIR")
	if dir == "":
		dir = "res://"
	elif not dir.ends_with("/"):
		dir += "/"
	# Let the window settle at its new size before the first grab.
	for i in 4:
		await RenderingServer.frame_post_draw
	var clip := OS.get_environment("SW_ANIM")
	if clip != "":
		await _shoot_anim(dir, clip)
	else:
		for a in ANGLES:
			$Turntable.rotation.y = deg_to_rad(a)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var err := img.save_png(dir + "shot_%03d.png" % int(a))
			print("shot %03d -> err=%d" % [int(a), err])
	get_tree().quit()

## Step one clip across its length and save a frame per step, so a cycle can
## be judged as a strip rather than guessed at from a single pose.
func _shoot_anim(dir: String, clip: String) -> void:
	var ap: AnimationPlayer = $Skinwalker/AnimationPlayer
	if not ap.has_animation(clip):
		push_error("no such clip: " + clip)
		return
	var ang := OS.get_environment("SW_ANGLE")
	$Turntable.rotation.y = deg_to_rad(float(ang) if ang != "" else 90.0)
	var an := ap.get_animation(clip)
	var length: float = an.length
	var steps := 8
	var cell := 384
	var sheet := Image.create(cell * 4, cell * 2, false, Image.FORMAT_RGBA8)
	ap.play(clip)
	for i in steps:
		ap.seek(length * float(i) / float(steps), true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell),
			Vector2i((i % 4) * cell, (i / 4) * cell))
	var err := sheet.save_png(dir + "anim_%s.png" % clip)
	print("anim %s -> sheet err=%d (%d frames over %.2fs)" % [clip, err, steps, length])
