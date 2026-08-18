extends RefCounted
## Hand-tuned PS1-era texture set for the Skinwalker.
##
## Everything is painted at native 256x256 -- there is no downsample of a
## high-res bake anywhere in here. Values are quantised into small palettes
## and sampled on a coarse pixel grid so wounds, ribs, fur and antler grain
## read as deliberate pixel clusters rather than mush.
##
## Produces four maps: albedo (with crevice AO painted in), normal (derived
## from a painted height field, not from albedo luminance), roughness, and
## emission (eyes only).

const Atlas := preload("res://tools/sw_atlas.gd")
const S := 256

var rng := RandomNumberGenerator.new()
var _n := FastNoiseLite.new()

var alb: Image
var hgt: Image   # scratch height field -> becomes the normal map
var rgh: Image
var emi: Image

func _init() -> void:
	rng.seed = 20260818
	_n.noise_type = FastNoiseLite.TYPE_VALUE
	alb = Image.create(S, S, false, Image.FORMAT_RGBA8)
	hgt = Image.create(S, S, false, Image.FORMAT_RGBA8)
	rgh = Image.create(S, S, false, Image.FORMAT_RGBA8)
	emi = Image.create(S, S, false, Image.FORMAT_RGBA8)
	alb.fill(Color(0, 0, 0, 1))
	hgt.fill(Color(0.5, 0.5, 0.5, 1))
	rgh.fill(Color(1, 1, 1, 1))
	emi.fill(Color(0, 0, 0, 1))

# ---------------------------------------------------------------- noise utils

## Blocky value noise: constant across a `cell`x`cell` pixel cluster.
func _cn(x: int, y: int, cell: int, freq: float, sd: int) -> float:
	var cx := float(x / cell)
	var cy := float(y / cell)
	_n.seed = 1337 + sd
	_n.frequency = freq
	return clampf(_n.get_noise_2d(cx, cy) * 0.5 + 0.5, 0.0, 1.0)

## Quantise t into `levels` bands, then pick from the palette.
func _pal(t: float, palette: Array, levels: int) -> Color:
	var band := floori(clampf(t, 0.0, 0.9999) * float(levels))
	var idx := clampi(int(round(float(band) / float(maxi(levels - 1, 1)) * float(palette.size() - 1))), 0, palette.size() - 1)
	return palette[idx]

func _px(img: Image, r: Rect2i, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= r.size.x or y >= r.size.y:
		return
	img.set_pixel(r.position.x + x, r.position.y + y, c)

func _get_h(r: Rect2i, x: int, y: int) -> float:
	var cx := clampi(x, 0, r.size.x - 1)
	var cy := clampi(y, 0, r.size.y - 1)
	return hgt.get_pixel(r.position.x + cx, r.position.y + cy).r

## Write one texel across all four maps.
func _emit(r: Rect2i, x: int, y: int, col: Color, h: float, rough: float, emis: Color = Color(0, 0, 0, 1)) -> void:
	_px(alb, r, x, y, col)
	_px(hgt, r, x, y, Color(h, h, h, 1))
	_px(rgh, r, x, y, Color(rough, rough, rough, 1))
	_px(emi, r, x, y, emis)

## Darken toward region edges -- a painted crevice/AO pass so each atlas tile
## still reads as a rounded form under flat vertex lighting.

func _edge_ao(r: Rect2i, x: int, y: int, strength: float) -> float:
	var fx := minf(float(x), float(r.size.x - 1 - x)) / float(r.size.x)
	var fy := minf(float(y), float(r.size.y - 1 - y)) / float(r.size.y)
	# Tight band at the very edge only, stepped -- a smooth full-tile vignette
	# would wash the quantised palette straight back into mush.
	var e := clampf(minf(fx, fy) * 7.0, 0.0, 1.0)
	e = floorf(e * 4.0) / 4.0
	return lerpf(1.0 - strength, 1.0, e)

# ------------------------------------------------------------------ painters

func paint_all() -> void:
	_paint_skin()
	_paint_belly()
	_paint_fur()
	_paint_furcard()
	_paint_gore()
	_paint_rib()
	_paint_skull()
	_paint_antler()
	_paint_teeth()
	_paint_mouth()
	_paint_eye()
	_paint_keratin("claw", [Color8(46, 40, 34), Color8(64, 56, 46), Color8(28, 24, 21), Color8(86, 76, 61)])
	_paint_keratin("hoof", [Color8(30, 26, 24), Color8(44, 38, 34), Color8(20, 17, 16), Color8(58, 50, 44)])
	_paint_sinew()
	_paint_wound()
	_paint_dark()
	_paint_blood()
	_paint_skin_limb()
	_paint_face()
	_paint_pelt()
	_build_normal()


func _paint_skin() -> void:
	var r: Rect2i = Atlas.R["skin"]
	var pal := [
		Color8(45, 33, 25), Color8(65, 49, 35), Color8(85, 64, 45),
		Color8(106, 81, 56), Color8(127, 98, 66), Color8(146, 114, 77),
	]
	var rough: float = Atlas.ROUGH["skin"]
	for y in r.size.y:
		for x in r.size.x:
			# Crisp small clusters riding on a broad tonal drift.
			var fine := _cn(x, y, 2, 0.42, 0)
			var broad := _cn(x, y, 8, 0.11, 7)
			var c := _pal(fine * 0.62 + broad * 0.38, pal, 6)
			var h := 0.42 + fine * 0.22
			# Creases and dirt pressed into the hide.
			if _cn(x, y, 2, 0.90, 4) > 0.86:
				c = c.darkened(0.45)
				h -= 0.10
			# Sparse scabbing / bruising, high contrast against the hide.
			var b := _cn(x, y, 3, 0.30, 3)
			if b > 0.84:
				c = c.lerp(Color8(84, 30, 21), 0.72)
				h -= 0.05
			elif b < 0.10:
				c = c.lerp(Color8(22, 16, 12), 0.75)
			var ao := _edge_ao(r, x, y, 0.30)
			_emit(r, x, y, Color(c.r * ao, c.g * ao, c.b * ao, 1.0), h, rough)


func _paint_belly() -> void:
	var r: Rect2i = Atlas.R["belly"]
	var pal := [
		Color8(63, 45, 36), Color8(86, 65, 50), Color8(108, 81, 62),
		Color8(126, 98, 73), Color8(143, 112, 84), Color8(158, 127, 96),
	]
	var rough: float = Atlas.ROUGH["belly"]
	for y in r.size.y:
		for x in r.size.x:
			var fine := _cn(x, y, 2, 0.38, 11)
			var broad := _cn(x, y, 8, 0.09, 14)
			var c := _pal(fine * 0.55 + broad * 0.45, pal, 6)
			# Thin taut skin: warm red reads through from underneath.
			c = c.lerp(Color8(133, 61, 43), _cn(x, y, 4, 0.16, 12) * 0.34)
			# Necrotic gray-green blotches creeping up from the pelvis.
			if _cn(x, y, 3, 0.26, 13) > 0.78:
				c = c.lerp(Color8(77, 76, 51), 0.70)
			# Stretch lines over the starved gut.
			if _cn(x / 3, y, 1, 0.75, 15) > 0.88:
				c = c.darkened(0.38)
			var ao := _edge_ao(r, x, y, 0.32)
			_emit(r, x, y, Color(c.r * ao, c.g * ao, c.b * ao, 1.0), 0.5 + fine * 0.12, rough)

func _paint_fur() -> void:
	var r: Rect2i = Atlas.R["fur"]
	var pal := [
		Color8(13, 10, 7), Color8(22, 16, 11), Color8(33, 25, 16),
		Color8(43, 33, 22), Color8(55, 42, 28),
	]
	var rough: float = Atlas.ROUGH["fur"]
	for y in r.size.y:
		for x in r.size.x:
			# Vertical matted strands: stretch the noise hard along Y.
			var strand := _cn(x, y / 6, 1, 0.30, 21)
			var t := strand * 0.72 + _cn(x, y, 2, 0.22, 22) * 0.28
			var c := _pal(t, pal, 5)
			if strand < 0.20:
				c = c.darkened(0.55)  # near-black parting where the coat splits
			# Coat thins toward the bottom of the tile (patchy coverage).
			c = c.lerp(Color8(64, 49, 35), clampf(float(y) / float(r.size.y), 0.0, 1.0) * 0.18)
			_emit(r, x, y, c, 0.35 + strand * 0.45, rough)

func _paint_furcard() -> void:
	var r: Rect2i = Atlas.R["furcard"]
	var pal := [Color8(9, 7, 5), Color8(18, 14, 10), Color8(29, 22, 15), Color8(40, 30, 21)]
	var rough: float = Atlas.ROUGH["furcard"]
	for y in r.size.y:
		for x in r.size.x:
			var strand := _cn(x, y / 4, 1, 0.34, 25)
			var c := _pal(strand, pal, 4)
			# Tuft tips (top of card) go darker so cards sink into the body.
			var tip := 1.0 - clampf(float(y) / float(r.size.y), 0.0, 1.0)
			c = c.darkened(tip * 0.45)
			_emit(r, x, y, c, 0.4 + strand * 0.3, rough)

func _paint_gore() -> void:
	var r: Rect2i = Atlas.R["gore"]
	var pal := [
		Color8(28, 5, 7), Color8(58, 10, 11), Color8(92, 16, 15),
		Color8(126, 26, 20), Color8(158, 46, 33),
	]
	var base: float = Atlas.ROUGH["gore"]
	for y in r.size.y:
		for x in r.size.x:
			var t := _cn(x, y, 2, 0.13, 31) * 0.65 + _cn(x, y, 4, 0.06, 32) * 0.35
			var c := _pal(t, pal, 5)
			var h := 0.4 + t * 0.3
			var rr := base
			# Wet highlights pool in the low spots: glossier and lighter.
			if _cn(x, y, 2, 0.20, 33) > 0.78:
				c = c.lerp(Color8(190, 84, 64), 0.5)
				rr = 0.10
			if t < 0.18:
				c = c.darkened(0.4)  # clotted near-black crust
				rr = 0.55
			var ao := _edge_ao(r, x, y, 0.30)
			_emit(r, x, y, Color(c.r * ao, c.g * ao, c.b * ao, 1.0), h, rr)

func _paint_rib() -> void:
	var r: Rect2i = Atlas.R["rib"]
	var pal := [
		Color8(150, 139, 112), Color8(176, 165, 136), Color8(200, 189, 160),
		Color8(218, 208, 179), Color8(234, 226, 200),
	]
	var rough: float = Atlas.ROUGH["rib"]
	for y in r.size.y:
		for x in r.size.x:
			var c := _pal(_cn(x, y, 2, 0.10, 41), pal, 5)
			# Bone runs lengthwise: bright crown down the middle of the tile,
			# grime settling along both edges.
			var mid := 1.0 - absf(float(y) / float(r.size.y) - 0.5) * 2.0
			c = c.lerp(Color8(224, 216, 190), mid * 0.35)
			c = c.lerp(Color8(84, 72, 54), (1.0 - mid) * 0.45)
			var h := 0.35 + mid * 0.45
			if _cn(x, y / 2, 1, 0.45, 42) > 0.86:
				c = c.lerp(Color8(70, 60, 44), 0.75)  # hairline crack / chip
				h -= 0.20
			if _cn(x, y, 3, 0.09, 43) > 0.82:
				c = c.lerp(Color8(96, 30, 24), 0.5)   # dried blood at the flesh line
			_emit(r, x, y, c, h, rough)


func _paint_skull() -> void:
	var r: Rect2i = Atlas.R["skull"]
	var pal := [
		Color8(77, 68, 51), Color8(98, 88, 67), Color8(121, 109, 84),
		Color8(142, 130, 102), Color8(161, 149, 120), Color8(177, 165, 135),
	]
	var rough: float = Atlas.ROUGH["skull"]
	for y in r.size.y:
		for x in r.size.x:
			var fine := _cn(x, y, 2, 0.40, 51)
			var c := _pal(fine * 0.6 + _cn(x, y, 8, 0.10, 52) * 0.4, pal, 6)
			# Connected wavy suture lines across the plate, not stray specks.
			var sut := absf(sin(float(y) * 0.85 + _cn(x, y, 4, 0.30, 53) * 3.0))
			if sut < 0.12:
				c = c.lerp(Color8(47, 40, 28), 0.80)
			# Grime and dried matter settling in the hollows.
			c = c.lerp(Color8(61, 49, 33), _cn(x, y, 3, 0.22, 54) * 0.35)
			var ao := _edge_ao(r, x, y, 0.28)
			_emit(r, x, y, Color(c.r * ao, c.g * ao, c.b * ao, 1.0), 0.4 + fine * 0.22, rough)

func _paint_antler() -> void:
	var r: Rect2i = Atlas.R["antler"]
	var pal := [
		Color8(71, 56, 35), Color8(91, 72, 46), Color8(113, 92, 60),
		Color8(133, 111, 75), Color8(152, 130, 91),
	]
	var rough: float = Atlas.ROUGH["antler"]
	for y in r.size.y:
		for x in r.size.x:
			# Antler grain runs along the beam (the V axis) as raised ridges.
			var ridge := _cn(x, y / 8, 1, 0.55, 61)
			var t := ridge * 0.55 + _cn(x, y, 2, 0.10, 62) * 0.45
			var c := _pal(t, pal, 5)
			var h := 0.30 + ridge * 0.55
			if ridge < 0.22:
				c = c.darkened(0.42)  # deep groove between ridges
				h -= 0.18
			# Bleached, chipped tips toward the top of the tile.
			var tipf := 1.0 - clampf(float(y) / float(r.size.y), 0.0, 1.0)
			c = c.lerp(Color8(166, 149, 117), tipf * tipf * 0.55)
			_emit(r, x, y, c, h, rough)

func _paint_teeth() -> void:
	var r: Rect2i = Atlas.R["teeth"]
	var pal := [Color8(142, 132, 108), Color8(168, 158, 132), Color8(192, 183, 157), Color8(210, 202, 178)]
	var rough: float = Atlas.ROUGH["teeth"]
	for y in r.size.y:
		for x in r.size.x:
			# Vertical tooth bands with dark gaps between them.
			var band := absf(sin(float(x) * 0.62))
			var c := _pal(band * 0.7 + _cn(x, y, 2, 0.2, 71) * 0.3, pal, 4)
			if band < 0.22:
				c = c.lerp(Color8(40, 30, 24), 0.7)
			# Rot creeping up from the gumline (bottom of tile).
			c = c.lerp(Color8(96, 66, 38), clampf(float(y) / float(r.size.y), 0.0, 1.0) * 0.45)
			if _cn(x, y, 2, 0.3, 72) > 0.88:
				c = c.lerp(Color8(88, 78, 60), 0.6)  # chipped / broken tip
			_emit(r, x, y, c, 0.35 + band * 0.45, rough)

func _paint_mouth() -> void:
	var r: Rect2i = Atlas.R["mouth"]
	var pal := [Color8(10, 4, 5), Color8(20, 7, 9), Color8(34, 11, 13), Color8(52, 17, 18)]
	var rough: float = Atlas.ROUGH["mouth"]
	for y in r.size.y:
		for x in r.size.x:
			var c := _pal(_cn(x, y, 2, 0.16, 81), pal, 4)
			var ao := _edge_ao(r, x, y, 0.55)
			_emit(r, x, y, Color(c.r * ao, c.g * ao, c.b * ao, 1.0), 0.5, rough)

func _paint_eye() -> void:
	var r: Rect2i = Atlas.R["eye"]
	var rough: float = Atlas.ROUGH["eye"]
	var iris := [Color8(96, 62, 16), Color8(134, 90, 24), Color8(168, 116, 34), Color8(196, 142, 46)]
	var cx := float(r.size.x) * 0.5
	var cy := float(r.size.y) * 0.5
	for y in r.size.y:
		for x in r.size.x:
			var d := Vector2(float(x) - cx, float(y) - cy).length() / (float(r.size.x) * 0.5)
			var c: Color
			var e := Color(0, 0, 0, 1)
			if d < 0.26:
				c = Color8(8, 5, 4)  # pupil: a dead black slot
			elif d < 0.60:
				# Dull amber iris, banded rather than smoothly graded.
				c = _pal(_cn(x, y, 2, 0.35, 91), iris, 4)
				# Bright amber core: these are meant to carry across a dark
				# forest, so the emission runs near full rather than sullen.
				e = Color(minf(1.0, c.r * 1.65), minf(1.0, c.g * 1.15), c.b * 0.35, 1.0)
			else:
				# Sunken socket rim swallowing the eye, with a faint bleed of
				# the glow onto it.
				c = Color8(30, 22, 18).lerp(Color8(12, 9, 8), clampf((d - 0.6) * 2.5, 0.0, 1.0))
				e = Color(0.22, 0.13, 0.03, 1.0) * (1.0 - clampf((d - 0.6) * 2.2, 0.0, 1.0))
			_emit(r, x, y, c, 0.6 - d * 0.3, rough, e)

func _paint_keratin(region: String, pal: Array) -> void:
	var r: Rect2i = Atlas.R[region]
	var rough: float = Atlas.ROUGH[region]
	for y in r.size.y:
		for x in r.size.x:
			# Lengthwise growth striations, like a real claw sheath.
			var stri := _cn(x, y / 6, 1, 0.5, 101)
			var c := _pal(stri * 0.6 + _cn(x, y, 2, 0.18, 102) * 0.4, pal, 4)
			var h := 0.35 + stri * 0.4
			# Tip (top of tile) polished lighter, base grimy.
			c = c.lerp(Color8(110, 100, 86), (1.0 - clampf(float(y) / float(r.size.y), 0.0, 1.0)) * 0.35)
			if stri > 0.90:
				c = c.darkened(0.5)  # split in the keratin
				h -= 0.2
			_emit(r, x, y, c, h, rough)

func _paint_sinew() -> void:
	var r: Rect2i = Atlas.R["sinew"]
	var pal := [Color8(96, 74, 62), Color8(122, 96, 78), Color8(146, 118, 96), Color8(168, 140, 116)]
	var rough: float = Atlas.ROUGH["sinew"]
	for y in r.size.y:
		for x in r.size.x:
			# Taut cords running the length of the tile.
			var cord := absf(sin(float(x) * 0.9 + _cn(x, y, 4, 0.1, 111) * 1.5))
			var c := _pal(cord * 0.75 + _cn(x, y, 2, 0.2, 112) * 0.25, pal, 4)
			if cord < 0.25:
				c = c.lerp(Color8(58, 38, 32), 0.6)
			_emit(r, x, y, c, 0.35 + cord * 0.4, rough)

func _paint_wound() -> void:
	var r: Rect2i = Atlas.R["wound"]
	var rough: float = Atlas.ROUGH["wound"]
	var wet := [Color8(120, 22, 18), Color8(152, 38, 28), Color8(96, 16, 14), Color8(176, 58, 40)]
	var dry := [Color8(70, 30, 24), Color8(92, 48, 36), Color8(64, 44, 36), Color8(48, 32, 28)]
	for y in r.size.y:
		for x in r.size.x:
			# Raw wet centre drying to a cracked crust at the tile edges.
			var fx := absf(float(x) / float(r.size.x) - 0.5) * 2.0
			var fy := absf(float(y) / float(r.size.y) - 0.5) * 2.0
			var edge := clampf(maxf(fx, fy) + _cn(x, y, 3, 0.15, 121) * 0.35 - 0.15, 0.0, 1.0)
			var c: Color
			var rr: float
			if edge < 0.55:
				c = _pal(_cn(x, y, 2, 0.18, 122), wet, 4)
				rr = rough
			else:
				c = _pal(_cn(x, y, 2, 0.22, 123), dry, 4)
				rr = 0.78
				if _cn(x, y / 2, 1, 0.5, 124) > 0.84:
					c = c.darkened(0.45)  # fissure in the scab
			_emit(r, x, y, c, 0.45 - edge * 0.15, rr)

func _paint_dark() -> void:
	var r: Rect2i = Atlas.R["dark"]
	var rough: float = Atlas.ROUGH["dark"]
	for y in r.size.y:
		for x in r.size.x:
			var c := Color8(12, 10, 10).lerp(Color8(26, 22, 21), _cn(x, y, 2, 0.2, 131))
			_emit(r, x, y, c, 0.5, rough)

# --------------------------------------------------------------- normal map

## Sobel the painted height field, clamped inside each region so no gradient
## ever samples across an atlas seam.
func _build_normal() -> void:
	var nrm := Image.create(S, S, false, Image.FORMAT_RGBA8)
	nrm.fill(Color(0.5, 0.5, 1.0, 1))
	for region in Atlas.R.keys():
		var r: Rect2i = Atlas.R[region]
		for y in r.size.y:
			for x in r.size.x:
				var dx := (_get_h(r, x - 1, y) - _get_h(r, x + 1, y)) * 3.0
				var dy := (_get_h(r, x, y - 1) - _get_h(r, x, y + 1)) * 3.0
				var n := Vector3(dx, dy, 1.0).normalized()
				nrm.set_pixel(
					r.position.x + x, r.position.y + y,
					Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0)
				)
	hgt = nrm  # hgt now holds the finished normal map

func save_all(dir: String) -> void:
	var e := 0
	e |= alb.save_png(dir + "skinwalker_albedo.png")
	e |= hgt.save_png(dir + "skinwalker_normal.png")
	e |= rgh.save_png(dir + "skinwalker_roughness.png")
	e |= emi.save_png(dir + "skinwalker_emission.png")
	print("  textures saved (err mask=%d) -> %s" % [e, dir])

# ------------------------------------------------- regions added on repack

func _paint_blood() -> void:
	var r: Rect2i = Atlas.R["blood"]
	var rough: float = Atlas.ROUGH["blood"]
	var pal := [Color8(22, 6, 7), Color8(52, 10, 11), Color8(88, 16, 15), Color8(124, 28, 22)]
	for y in r.size.y:
		for x in r.size.x:
			# Drips run down the tile: a column either carries blood or does not,
			# and the ones that do fade out partway down.
			var col := _cn(x, 0, 2, 0.9, 141)
			var run := clampf(float(y) / float(r.size.y), 0.0, 1.0)
			var carries := col > 0.44
			var c: Color
			var rr := rough
			if carries and run < col * 1.4:
				c = _pal(_cn(x, y, 2, 0.3, 142), pal, 4)
				if _cn(x, y, 2, 0.5, 143) > 0.80:
					c = c.lerp(Color8(168, 54, 38), 0.55)  # wet highlight on the run
			else:
				c = Color8(16, 11, 10).lerp(Color8(34, 22, 19), _cn(x, y, 3, 0.25, 144))
				rr = 0.85
			_emit(r, x, y, c, 0.45 + (0.15 if carries else 0.0), rr)

func _paint_skin_limb() -> void:
	var r: Rect2i = Atlas.R["skinlimb"]
	var pal := [
		Color8(39, 29, 20), Color8(57, 41, 28), Color8(76, 56, 38),
		Color8(95, 71, 46), Color8(115, 86, 56), Color8(134, 100, 66),
	]
	var rough: float = Atlas.ROUGH["skinlimb"]
	for y in r.size.y:
		for x in r.size.x:
			var fine := _cn(x, y, 2, 0.46, 151)
			var c := _pal(fine * 0.65 + _cn(x, y, 8, 0.13, 152) * 0.35, pal, 6)
			# Tendons stand out hard under skin this thin -- cords along the limb.
			# Cords wander in both phase and strength; a clean sine here turns
			# a 6-sided limb tube into corduroy.
			var cord := absf(sin(float(x) * 0.52 + _cn(x, y, 5, 0.22, 153) * 3.4))
			cord = cord * (0.55 + _cn(x, y, 7, 0.09, 155) * 0.45)
			c = c.lerp(Color8(118, 88, 57), clampf(cord - 0.74, 0.0, 1.0) * 1.2)
			if cord < 0.13:
				c = c.darkened(0.32)  # hollow between the cords
			if _cn(x, y, 3, 0.34, 154) > 0.88:
				c = c.lerp(Color8(78, 27, 17), 0.6)  # raw abrasion
			var ao := _edge_ao(r, x, y, 0.30)
			_emit(r, x, y, Color(c.r * ao, c.g * ao, c.b * ao, 1.0), 0.4 + cord * 0.25, rough)

func _paint_face() -> void:
	var r: Rect2i = Atlas.R["face"]
	var pal := [
		Color8(36, 27, 21), Color8(55, 42, 30), Color8(74, 58, 41),
		Color8(96, 75, 53), Color8(117, 93, 65), Color8(137, 109, 77),
	]
	var rough: float = Atlas.ROUGH["face"]
	for y in r.size.y:
		for x in r.size.x:
			var fv := clampf(float(y) / float(r.size.y), 0.0, 1.0)
			var fine := _cn(x, y, 2, 0.44, 161)
			var c := _pal(fine * 0.6 + _cn(x, y, 8, 0.12, 162) * 0.4, pal, 6)
			# Dark across the bridge (top of tile), paling toward the muzzle.
			c = c.lerp(Color8(28, 21, 16), (1.0 - fv) * 0.55)
			c = c.lerp(Color8(146, 119, 86), clampf(fv - 0.55, 0.0, 1.0) * 0.9)
			# Bloodied, ragged lip line along the bottom edge.
			if fv > 0.80:
				var lip := _cn(x, y, 2, 0.4, 163)
				c = c.lerp(Color8(92, 20, 14), clampf((fv - 0.80) * 5.0, 0.0, 1.0) * (0.45 + lip * 0.45))
			var ao := _edge_ao(r, x, y, 0.26)
			_emit(r, x, y, Color(c.r * ao, c.g * ao, c.b * ao, 1.0), 0.42 + fine * 0.2, rough)

func _paint_pelt() -> void:
	var r: Rect2i = Atlas.R["pelt"]
	var fur_pal := [Color8(10, 8, 6), Color8(19, 15, 10), Color8(30, 23, 16), Color8(42, 32, 22)]
	var hide_pal := [Color8(64, 49, 36), Color8(84, 65, 47), Color8(103, 80, 58)]
	var rough: float = Atlas.ROUGH["pelt"]
	for y in r.size.y:
		for x in r.size.x:
			var strand := _cn(x, y / 5, 1, 0.38, 171)
			# Coverage is patchy: where the coat gives out, bare hide shows.
			var cover := _cn(x, y, 6, 0.16, 172)
			var c: Color
			var h: float
			if cover > 0.38:
				c = _pal(strand, fur_pal, 4)
				h = 0.40 + strand * 0.45
				if strand < 0.22:
					c = c.darkened(0.5)  # parting in the coat
			else:
				c = _pal(_cn(x, y, 2, 0.4, 173), hide_pal, 3)
				h = 0.30
				# Ragged fur edge feathering onto the bald patch.
				if strand > 0.72:
					c = c.lerp(Color8(26, 21, 14), 0.6)
			_emit(r, x, y, c, h, rough)
