extends MainLoop
## Builds the muzzle flash asset: a small emissive 3D flame, its material, and
## a self-contained scene that flashes once per shot.
##
##   godot --headless --path . --script res://tools/build_weapon.gd
##
## The flash is real geometry rather than a billboard sprite so it holds up when
## the player strafes past it, and it is built from three flame petals rolled
## around the bore plus a hot core -- readable from any angle for ~30 triangles.

const MESH_PATH := "res://models/weapons/muzzle_flash.res"
const MAT_PATH := "res://materials/muzzle_flash.tres"
const SCENE_PATH := "res://scenes/props/MuzzleFlash.tscn"

## Flame silhouette, as [radius from bore, distance forward]. Widens just past
## the muzzle then tapers to a point, the way a real flash does.
const PROFILE := [
	[0.026, 0.00], [0.110, -0.06], [0.160, -0.18], [0.084, -0.34], [0.0, -0.48],
]

var v_pos := PackedVector3Array()
var v_col := PackedColorArray()
var v_nrm := PackedVector3Array()

func _initialize() -> void:
	_build_petals()
	_build_core()
	var mesh := _commit()
	ResourceSaver.save(mesh, MESH_PATH)
	mesh.take_over_path(MESH_PATH)
	print("muzzle flash: %d tris" % (v_pos.size() / 3))
	_save_scene(mesh)
	print("WEAPON_BUILD_DONE")

## Hot white at the muzzle, fading to deep orange at the tip.
func _heat(t: float) -> Color:
	# Additive blending sums where the three petals cross, so the base colour is
	# kept well under white or the whole flash saturates to a flat blob.
	return Color(0.95, 0.78, 0.38).lerp(Color(0.85, 0.24, 0.03), clampf(t, 0.0, 1.0))

func _tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (b - a).cross(c - a)
	n = n.normalized() if n.length_squared() > 1e-12 else Vector3.BACK
	for p in [[a, ca], [b, cb], [c, cc]]:
		v_pos.append(p[0])
		v_col.append(p[1])
		v_nrm.append(n)

## Emitted both ways: the flash is unshaded and additive, and a culled back
## face would make it vanish from half the angles.
func _quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri(a, b, c, ca, cb, cc)
	_tri(a, c, d, ca, cc, cd)
	_tri(a, c, b, ca, cc, cb)
	_tri(a, d, c, ca, cd, cc)

func _build_petals() -> void:
	for i in 3:
		var ang := PI * float(i) / 3.0
		var right := Vector3(cos(ang), sin(ang), 0.0)
		for k in range(PROFILE.size() - 1):
			var r0: float = PROFILE[k][0]
			var z0: float = PROFILE[k][1]
			var r1: float = PROFILE[k + 1][0]
			var z1: float = PROFILE[k + 1][1]
			var t0 := float(k) / float(PROFILE.size() - 1)
			var t1 := float(k + 1) / float(PROFILE.size() - 1)
			_quad2(
				right * -r0 + Vector3(0, 0, z0), right * r0 + Vector3(0, 0, z0),
				right * r1 + Vector3(0, 0, z1), right * -r1 + Vector3(0, 0, z1),
				_heat(t0), _heat(t0), _heat(t1), _heat(t1))

## Small blown-out ball right at the bore, so the base of the flash reads as a
## solid burst instead of three intersecting cards.
func _build_core() -> void:
	var sides := 6
	var r := 0.058
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0.0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0.0)
		_tri(Vector3(0, 0, 0.03), p0, p1, _heat(0.0), _heat(0.35), _heat(0.35))
		_tri(Vector3(0, 0, -0.09), p1, p0, _heat(0.15), _heat(0.35), _heat(0.35))

func _commit() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v_pos
	arr[Mesh.ARRAY_NORMAL] = v_nrm
	arr[Mesh.ARRAY_COLOR] = v_col
	var idx := PackedInt32Array()
	idx.resize(v_pos.size())
	for i in v_pos.size():
		idx[i] = i
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.30)
	mat.emission_energy_multiplier = 1.1
	ResourceSaver.save(mat, MAT_PATH)
	mat.take_over_path(MAT_PATH)
	m.surface_set_material(0, mat)
	return m

func _save_scene(mesh: ArrayMesh) -> void:
	var root := Node3D.new()
	root.name = "MuzzleFlash"
	root.set_script(load("res://scripts/muzzle_flash.gd"))
	root.visible = false

	var mi := MeshInstance3D.new()
	mi.name = "Flame"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	var lamp := OmniLight3D.new()
	lamp.name = "FlashLight"
	lamp.position = Vector3(0, 0, -0.12)
	lamp.light_color = Color(1.0, 0.80, 0.45)
	lamp.light_energy = 5.5
	lamp.omni_range = 9.0
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = false
	root.add_child(lamp)

	for c in root.get_children():
		c.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, SCENE_PATH)
	root.free()
	print("  saved %s" % SCENE_PATH)

func _process(_d: float) -> bool:
	return true
