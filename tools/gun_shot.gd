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

	# 2. the instant of the shot -- flash still up
	player.shoot()
	await _grab(sheet, 1)

	# 3. deep in the recoil, flash gone
	for i in 6:
		await RenderingServer.frame_post_draw
	await _grab(sheet, 2)

	# 4. aimed down the sights, settled
	Input.action_press("aim")
	for i in 45:
		await RenderingServer.frame_post_draw
	await _grab(sheet, 3)
	Input.action_release("aim")

	print("gun sheet err=%d" % sheet.save_png(dir + "gun_test.png"))
	get_tree().quit()
