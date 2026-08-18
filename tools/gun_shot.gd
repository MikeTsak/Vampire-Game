extends Node3D
## Drives the gun test: fires a shot and grabs frames around it, then repeats
## while aiming, so the flash, the recoil and the sight picture can all be
## checked from one run. Writes a contact sheet to $GUN_SHOT_DIR.

const CELL := 384

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(CELL * 2, CELL * 2))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_run")

func _grab(sheet: Image, slot: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(CELL, CELL, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL),
		Vector2i((slot % 2) * CELL, (slot / 2) * CELL))

func _run() -> void:
	# The audio probe drives its own timeline and quits when done; two drivers
	# racing to quit() cuts whichever is slower off mid-run.
	if OS.get_environment("GUN_AUDIO_PROBE") == "1":
		return
	var dir := OS.get_environment("GUN_SHOT_DIR")
	if dir == "":
		dir = "res://"
	elif not dir.ends_with("/"):
		dir += "/"
	var player: Node = $Player
	for i in 12:
		await RenderingServer.frame_post_draw

	var sheet := Image.create(CELL * 2, CELL * 2, false, Image.FORMAT_RGBA8)

	# 1. hip carry, at rest
	await _grab(sheet, 0)

	# 2. shouldered and settled -- the sight picture.
	# GUN_HIP=1 runs the same beats from the hip, to check the full sway still
	# plays there and that only the aimed case is damped.
	var hip := OS.get_environment("GUN_HIP") == "1"
	if not hip:
		Input.action_press("aim")
	await get_tree().create_timer(0.9).timeout
	await _grab(sheet, 1)

	# 3 & 4. fire WHILE shouldered and catch the bolt cycle mid-swing. This is
	# the case that was clipping the rifle through the near plane.
	player.shoot()
	await get_tree().create_timer(0.35).timeout
	await _grab(sheet, 2)
	await get_tree().create_timer(0.55).timeout
	await _grab(sheet, 3)
	if not hip:
		Input.action_release("aim")

	print("gun sheet err=%d" % sheet.save_png(dir + "gun_test.png"))
	get_tree().quit()
