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

func _run() -> void:
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
