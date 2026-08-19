extends MainLoop
## Builds the player's first-person hands + sleeves: a chunky, squared,
## Pixar-"Up"-inspired veteran's hands gripping the rifle, cut as their own
## primitives so they read as flesh-and-wool rather than more gun.
##
##   godot --headless --path . --script res://tools/build_hands.gd
##
## Paints a small pixel atlas (skin over wool), crops it into two standalone
## textures, and assembles PlayerHands.tscn as pure CSG box primitives -- no
## dependency on the rifle mesh at all, so the hands can be repositioned or
## animated on their own later without touching WWIRifle.

const ATLAS_PNG := "res://textures/hands_atlas.png"
const SKIN_TEX := "res://textures/hand_skin.tres"
const FABRIC_TEX := "res://textures/hand_fabric.tres"
const SCENE_PATH := "res://scenes/characters/PlayerHands.tscn"

const TILE := 64

var _n := FastNoiseLite.new()

func _initialize() -> void:
	_n.noise_type = FastNoiseLite.TYPE_VALUE

	var atlas := _paint_atlas()
	atlas.save_png(ATLAS_PNG)
	var skin_img := atlas.get_region(Rect2i(0, 0, TILE * 2, TILE))
	var fabric_img := atlas.get_region(Rect2i(0, TILE, TILE * 2, TILE))
	_save_tex(skin_img, SKIN_TEX)
	_save_tex(fabric_img, FABRIC_TEX)

	var skin_mat := _make_material(load(SKIN_TEX))
	var fabric_mat := _make_material(load(FABRIC_TEX))
	# A little tiling keeps the big forearm slabs from reading as one flat
	# swatch, without risking any atlas-seam bleed -- each texture is a
	# dedicated crop, not a shared sub-rect.
	fabric_mat.uv1_scale = Vector3(1.6, 1.6, 1.6)

	_build_scene(skin_mat, fabric_mat)
	print("BUILD_HANDS_DONE")

func _process(_d: float) -> bool:
	return true

# ------------------------------------------------------------------ texture

func _cn(x: int, y: int, cell: int, freq: float, seed: int) -> float:
	var cx := float(x / cell)
	var cy := float(y / cell)
	_n.seed = 4000 + seed
	_n.frequency = freq
	return clampf(_n.get_noise_2d(cx, cy) * 0.5 + 0.5, 0.0, 1.0)

func _pal(t: float, palette: Array, levels: int) -> Color:
	var band := floori(clampf(t, 0.0, 0.9999) * float(levels))
	var idx := clampi(int(round(float(band) / float(maxi(levels - 1, 1)) * float(palette.size() - 1))), 0, palette.size() - 1)
	return palette[idx]

## 128x128: weathered hide on top, coarse wool on the bottom. Painted evenly
## across the whole tile (no edge vignette) so a primitive that only ever
## samples a small UV window still reads as representative skin or fabric.
func _paint_atlas() -> Image:
	var w := TILE * 2
	var img := Image.create(w, TILE * 2, false, Image.FORMAT_RGBA8)

	var skin_pal := [
		Color8(94, 68, 49), Color8(115, 86, 61), Color8(133, 103, 72),
		Color8(151, 119, 85), Color8(168, 135, 98), Color8(184, 150, 111),
	]
	for y in TILE:
		for x in w:
			var fine := _cn(x, y, 2, 0.40, 1)
			var broad := _cn(x, y, 6, 0.10, 2)
			var c := _pal(fine * 0.6 + broad * 0.4, skin_pal, 6)
			# Deep creases across the knuckles and weathering in the hide.
			if _cn(x, y, 2, 0.85, 3) > 0.87:
				c = c.darkened(0.4)
			# Sparse sun/age spots -- a hardened veteran's hands, not a boy's.
			if _cn(x, y, 3, 0.28, 4) > 0.90:
				c = c.lerp(Color8(70, 48, 33), 0.6)
			img.set_pixel(x, y, c)

	var fab_pal := [
		Color8(42, 45, 30), Color8(56, 59, 40), Color8(70, 72, 49),
		Color8(84, 85, 58), Color8(97, 97, 67),
	]
	for y in TILE:
		for x in w:
			var weave := _cn(x, y, 1, 0.9, 5) * 0.5 + _cn(x, y, 3, 0.2, 6) * 0.5
			var c := _pal(weave, fab_pal, 5)
			# Worn, sun-bleached patches in the wool.
			if _cn(x, y, 4, 0.16, 7) > 0.82:
				c = c.lerp(Color8(107, 104, 82), 0.5)
			img.set_pixel(x, TILE + y, c)
	return img

func _save_tex(img: Image, path: String) -> void:
	var tex := ImageTexture.create_from_image(img)
	var err := ResourceSaver.save(tex, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])

func _make_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	return m

# -------------------------------------------------------------------- scene

func _add_box(parent: Node3D, name: String, pos: Vector3, size: Vector3,
		rot_deg: Vector3, mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = name
	b.position = pos
	b.rotation_degrees = rot_deg
	b.size = size
	b.material_override = mat
	# The gun deliberately excludes itself from the flashlight's shadow pass
	# (layer 3 / shadow_caster_mask). Hands stay on the default layer and get
	# shadows turned on explicitly so they throw real dynamic shadows.
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(b)
	return b

## One chunky glove-and-cuff assembly, wrapped around whatever point on the
## rifle it holds. `mirror` flips the thumb/lean side for the off hand so the
## same layout serves both without duplicating it by hand.
## Overall hand scale. First pass read as an ambiguous blob half-buried in
## the grip mesh -- bigger fingers that clearly stand proud of the grip's own
## CSG box read as a hand wrapping it instead of two shapes intersecting.
const S := 1.35

func _build_hand(root: Node3D, name: String, origin: Vector3, tilt_deg: Vector3,
		mirror: bool, skin: Material, fabric: Material) -> void:
	var side := -1.0 if mirror else 1.0
	var grp := Node3D.new()
	grp.name = name
	grp.position = origin
	grp.rotation_degrees = tilt_deg
	root.add_child(grp)

	# Wide square palm block -- everything else hangs off this.
	_add_box(grp, "Palm", Vector3.ZERO, Vector3(0.10, 0.085, 0.11) * S, Vector3.ZERO, skin)

	# Four blocky fingers curled down and OUT in front of the palm, so they
	# read as wrapping around the grip/forend rather than sitting inside it.
	for i in 4:
		var fx := (float(i) - 1.5) * 0.030 * S
		_add_box(grp, "Finger%d" % i, Vector3(fx, -0.01 * S, 0.13 * S),
			Vector3(0.024, 0.026, 0.09) * S, Vector3(-48, 0, 0), skin)

	# Thumb, angled off to the side and wrapping back the other way.
	_add_box(grp, "Thumb", Vector3(0.07 * side * S, 0.02 * S, 0.03 * S),
		Vector3(0.028, 0.028, 0.075) * S, Vector3(-12, 0, 50 * side), skin)

	# Raised knuckle ridge so the fist reads under flat retro lighting
	# instead of vanishing into one smooth block.
	_add_box(grp, "Knuckles", Vector3(0.0, 0.032 * S, 0.075 * S),
		Vector3(0.096, 0.02, 0.035) * S, Vector3(-18, 0, 0), skin)

	# Cuff -- where hide meets wool, slightly flared over the wrist.
	_add_box(grp, "Cuff", Vector3(0.0, -0.01 * S, -0.12 * S),
		Vector3(0.125, 0.105, 0.065) * S, Vector3.ZERO, fabric)

	# Forearm, receding down and back toward the body (mostly off the bottom
	# of the frame, the way a real FPS viewmodel arm exits the screen).
	_add_box(grp, "ForearmNear", Vector3(0.03 * side * S, -0.10 * S, 0.06 * S),
		Vector3(0.135, 0.145, 0.165) * S, Vector3(0, 0, -6 * side), fabric)
	_add_box(grp, "ForearmFar", Vector3(0.06 * side * S, -0.22 * S, 0.11 * S),
		Vector3(0.15, 0.165, 0.195) * S, Vector3(0, 0, -10 * side), fabric)

func _build_scene(skin: Material, fabric: Material) -> void:
	var root := Node3D.new()
	root.name = "PlayerHands"

	# Right hand on the pistol grip (rifle-local space -- same frame as
	# WWIRifle's own children, since both sit at the WeaponPivot origin).
	# Nudged forward and up from the grip's own CSG box so the fingers curl
	# in front of it rather than co-occupying the same space.
	_build_hand(root, "HandGrip", Vector3(0.0, -0.065, 0.42), Vector3(-12, 0, 0),
		false, skin, fabric)
	# Left hand supporting the forend, further toward the muzzle.
	_build_hand(root, "HandForend", Vector3(0.0, -0.045, -0.16), Vector3(4, 0, 0),
		true, skin, fabric)

	_set_owner(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, SCENE_PATH)
	root.free()
	if err != OK:
		push_error("save failed: %d" % err)
	else:
		print("  saved %s" % SCENE_PATH)

func _set_owner(n: Node, own: Node) -> void:
	for c in n.get_children():
		c.owner = own
		_set_owner(c, own)
