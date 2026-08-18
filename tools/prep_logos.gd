extends MainLoop
## Downscales the supplied brand logos to UI-sane sizes and trims any
## transparent margin. Originals are 4096x4096 and 3200x1320 -- far more than a
## menu needs, and ~24MB of VRAM between them if used raw.
##
## Resize happens BEFORE the alpha trim on purpose: scanning 16.7M pixels from
## GDScript takes minutes, and trimming the downscaled copy is visually identical.

const SRC := "C:/Users/mixan/AppData/Local/Temp/claude/x--Vampire-Game/1890fbe6-f322-4316-b9a5-6a19086784b6/scratchpad/brand/"
const OUT := "res://textures/branding/"

func _initialize() -> void:
	_do("att.png", "att_logo.png", 512)
	_do("aa.png", "agileadvisors_logo.png", 512)
	_make_glow(OUT + "logo_glow.png", 256)
	print("LOGOS_DONE")

## Alpha bounding box, read straight off the raw buffer rather than get_pixel().
func _alpha_bounds(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		var row := y * w * 4
		for x in w:
			if d[row + x * 4 + 3] > 6:
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
	if x1 < 0:
		return Rect2i(0, 0, w, h)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _do(src_name: String, out_name: String, longest: int) -> void:
	var bytes := FileAccess.get_file_as_bytes(SRC + src_name)
	if bytes.is_empty():
		push_error("could not read " + SRC + src_name)
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		push_error("bad png " + src_name)
		return
	var before := "%dx%d" % [img.get_width(), img.get_height()]

	var scale: float = float(longest) / float(maxi(img.get_width(), img.get_height()))
	if scale < 1.0:
		img.resize(maxi(1, int(round(img.get_width() * scale))),
			maxi(1, int(round(img.get_height() * scale))), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)

	var box := _alpha_bounds(img)
	if box.size.x < img.get_width() or box.size.y < img.get_height():
		img = img.get_region(box)
	img.save_png(OUT + out_name)
	print("  %-26s %s -> %dx%d" % [out_name, before, img.get_width(), img.get_height()])

## Soft radial glow used behind the ATT mark. Both supplied logos are drawn for
## light backgrounds -- their black linework disappears on the near-black menu --
## so the mark needs something luminous behind it to read against.
func _make_glow(path: String, size: int) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.5)
			img.set_pixel(x, y, Color(0.56, 0.45, 0.43, a))
	img.save_png(path)
	print("  %-26s %dx%d radial glow" % [path.get_file(), size, size])
