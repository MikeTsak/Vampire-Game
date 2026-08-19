extends RefCounted
## Skinned mesh builder for the Skinwalker.
##
## Deliberately flat-shaded: every triangle gets its own three vertices and a
## true face normal, so the facets stay visible instead of being smoothed into
## a modern rounded read. Lighting is carried mostly by baked vertex AO, which
## is the retro way and survives the per-vertex shading mode the material uses.
##
## Skinning is automatic but fenced: each part declares a whitelist of bones,
## and vertices are weighted only against those. That keeps the jaw off the
## cranium and one finger off the next without any hand-painted weights.

const Atlas := preload("res://tools/sw_atlas.gd")

## Godot's front face is counter-clockwise when the triangle is viewed from
## outside. tri() first orients each triangle against the outward normal it is
## handed, then this flag applies the winding convention on top.
##
## Getting this backwards is nastier than it sounds: a closed convex form keeps
## its silhouette either way -- you simply see the inside of the far wall lit by
## an outward normal -- so the torso looked merely a bit flat. It only became
## obvious on the skull, where the muzzle sits inside the cranium and the far
## interior showed straight through.
const WIND_CW := false

var bone_names: PackedStringArray = PackedStringArray()
var bone_pos: Array = []
var bone_tail: Array = []

var v_pos := PackedVector3Array()
var v_nrm := PackedVector3Array()
var v_uv := PackedVector2Array()
var v_col := PackedColorArray()
var v_bone := PackedInt32Array()
var v_wt := PackedFloat32Array()

var _wl := PackedInt32Array()
var _ao := 1.0
var _region := "skin"
var _tris := 0

func setup(bones: Array) -> void:
	for b in bones:
		bone_names.append(b["name"])
		bone_pos.append(b["pos"])
		bone_tail.append(b["tail"])

func bone_idx(n: String) -> int:
	return bone_names.find(n)

## Resolve a whitelist entry list into bone indices. An entry ending in "*"
## is a prefix match, so "Finger2_*.L" style groups stay terse at the callsite.
func _resolve(names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in names:
		var s := String(n)
		if s.ends_with("*"):
			var pre := s.substr(0, s.length() - 1)
			for i in bone_names.size():
				if bone_names[i].begins_with(pre) and not out.has(i):
					out.append(i)
		else:
			var i := bone_names.find(s)
			if i >= 0 and not out.has(i):
				out.append(i)
			elif i < 0:
				push_error("sw_mesh: unknown bone in whitelist: %s" % s)
	return out

## Begin a part. `ao` is a hand-authored occlusion multiplier for geometry the
## analytic sky term cannot know about (mouth interior, inside the ribcage).
func begin(whitelist: Array, region: String, ao: float = 1.0) -> void:
	_wl = _resolve(whitelist)
	_region = region
	_ao = ao
	if _wl.is_empty():
		push_error("sw_mesh: empty whitelist for region %s" % region)

func _dist_to_bone(v: Vector3, bi: int) -> float:
	var a: Vector3 = bone_pos[bi]
	var b: Vector3 = bone_tail[bi]
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return v.distance_to(a)
	var t := clampf((v - a).dot(ab) / l2, 0.0, 1.0)
	return v.distance_to(a + ab * t)

## Inverse-distance weighting against the whitelist, top 4, normalised.
## The 4th power keeps influence tight so a long forearm does not smear
## weight up into the shoulder.
func _skin(v: Vector3) -> Array:
	var pairs := []
	for bi in _wl:
		var d := _dist_to_bone(v, bi)
		pairs.append([bi, pow(1.0 / (d + 0.02), 4.0)])
	pairs.sort_custom(func(x, y): return x[1] > y[1])
	var ids := [0, 0, 0, 0]
	var wts := [0.0, 0.0, 0.0, 0.0]
	var total := 0.0
	for i in mini(4, pairs.size()):
		ids[i] = pairs[i][0]
		wts[i] = pairs[i][1]
		total += pairs[i][1]
	if total <= 0.0:
		ids[0] = _wl[0]
		wts[0] = 1.0
	else:
		for i in 4:
			wts[i] /= total
	return [ids, wts]

## Analytic sky occlusion -- upward faces catch light, undersides go dark.
func _vcol(n: Vector3) -> Color:
	var sky := 0.70 + 0.30 * (n.y * 0.5 + 0.5)
	var a := clampf(sky * _ao, 0.0, 1.0)
	return Color(a, a, a, 1.0)

func _push(p: Vector3, n: Vector3, uv: Vector2) -> void:
	v_pos.append(p)
	v_nrm.append(n)
	v_uv.append(uv)
	v_col.append(_vcol(n))
	var sk := _skin(p)
	for i in 4:
		v_bone.append(sk[0][i])
		v_wt.append(sk[1][i])

## Emit one flat-shaded triangle, wound so it faces `outward`.
func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, outward: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot(outward) < 0.0:
		var t := b; b = c; c = t
		var tu := ub; ub = uc; uc = tu
		n = -n
	if not WIND_CW:
		var t2 := b; b = c; c = t2
		var tu2 := ub; ub = uc; uc = tu2
	_push(a, n, ua)
	_push(b, n, ub)
	_push(c, n, uc)
	_tris += 1

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, outward: Vector3) -> void:
	tri(a, b, c, ua, ub, uc, outward)
	tri(a, c, d, ua, uc, ud, outward)

## UV helper into the current region.
func u(uu: float, vv: float) -> Vector2:
	return Atlas.uv(_region, uu, vv)

func tri_count() -> int:
	return _tris

# ------------------------------------------------------------- primitives

## Parallel-transported frames along a path, so a tube never twists as it
## bends round the hock or the antler beam.
func _frames(path: Array) -> Array:
	var n := path.size()
	var tan := []
	for i in n:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n - 1:
			t = path[n - 1] - path[n - 2]
		else:
			t = (path[i + 1] - path[i - 1])
		tan.append(t.normalized() if t.length() > 1e-6 else Vector3.FORWARD)
	var t0: Vector3 = tan[0]
	var ref := Vector3.UP
	if absf(t0.dot(ref)) > 0.95:
		ref = Vector3.RIGHT
	var nrm := (ref - t0 * ref.dot(t0)).normalized()
	var out := [[t0, nrm, t0.cross(nrm).normalized()]]
	for i in range(1, n):
		var prev_t: Vector3 = tan[i - 1]
		var cur_t: Vector3 = tan[i]
		var prev_n: Vector3 = out[i - 1][1]
		var axis := prev_t.cross(cur_t)
		var cur_n := prev_n
		if axis.length() > 1e-6:
			cur_n = prev_n.rotated(axis.normalized(), prev_t.angle_to(cur_t))
		cur_n = (cur_n - cur_t * cur_n.dot(cur_t)).normalized()
		out.append([cur_t, cur_n, cur_t.cross(cur_n).normalized()])
	return out

## Swept tube. `squash` optionally gives a per-ring Vector2 so a cross-section
## can be flattened (the torso is deeper than it is wide).
## `v_tile` > 0 ping-pongs V every that-many metres -- mirror repeat, so a long
## limb keeps texel density without ever cutting a UV seam mid-face.
func tube(path: Array, radii: Array, sides: int, v0: float = 0.0, v1: float = 1.0,
		cap_start: bool = false, cap_end: bool = false,
		squash: Array = [], v_tile: float = 0.0) -> void:
	var n := path.size()
	if n < 2:
		return
	var fr := _frames(path)
	var run := [0.0]
	for i in range(1, n):
		run.append(run[i - 1] + (path[i] as Vector3).distance_to(path[i - 1]))

	var ring := []
	var vcoord := []
	for i in n:
		var sq: Vector2 = squash[i] if i < squash.size() else Vector2.ONE
		var pts := []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var off: Vector3 = (fr[i][1] as Vector3) * (cos(a) * sq.x) + (fr[i][2] as Vector3) * (sin(a) * sq.y)
			pts.append((path[i] as Vector3) + off * float(radii[i]))
		ring.append(pts)
		if v_tile > 0.0:
			var tw: float = float(run[i]) / v_tile
			vcoord.append(absf(fmod(tw, 2.0) - 1.0))  # triangle wave: mirror repeat
		else:
			vcoord.append(lerpf(v0, v1, float(i) / float(n - 1)))

	for i in range(n - 1):
		for k in sides:
			var k2 := (k + 1) % sides
			var a: Vector3 = ring[i][k]
			var b: Vector3 = ring[i][k2]
			var c: Vector3 = ring[i + 1][k2]
			var d: Vector3 = ring[i + 1][k]
			var mid := (a + b + c + d) * 0.25
			var axis := ((path[i] as Vector3) + (path[i + 1] as Vector3)) * 0.5
			var outward := (mid - axis).normalized()
			var uk := float(k) / float(sides)
			var uk2 := float(k + 1) / float(sides)
			quad(a, b, c, d,
				u(uk, vcoord[i]), u(uk2, vcoord[i]), u(uk2, vcoord[i + 1]), u(uk, vcoord[i + 1]),
				outward)

	if cap_start:
		_cap(ring[0], path[0], -(fr[0][0] as Vector3), vcoord[0])
	if cap_end:
		_cap(ring[n - 1], path[n - 1], fr[n - 1][0], vcoord[n - 1])

func _cap(pts: Array, centre: Vector3, outward: Vector3, vv: float) -> void:
	var s := pts.size()
	for k in s:
		var k2 := (k + 1) % s
		tri(centre, pts[k], pts[k2], u(0.5, vv), u(float(k) / float(s), vv), u(float(k + 1) / float(s), vv), outward)

## Oriented box. `uvs` optionally gives per-face [u0,v0,u1,v1] sub-rects; by
## default every face samples the whole region.
func box(centre: Vector3, size: Vector3, basis: Basis = Basis()) -> void:
	var h := size * 0.5
	var c := []
	for i in 8:
		var s := Vector3(
			h.x if (i & 1) else -h.x,
			h.y if (i & 2) else -h.y,
			h.z if (i & 4) else -h.z)
		c.append(centre + basis * s)
	# (indices, outward local axis)
	var faces := [
		[[0, 2, 6, 4], Vector3.LEFT], [[1, 5, 7, 3], Vector3.RIGHT],
		[[0, 4, 5, 1], Vector3.DOWN], [[2, 3, 7, 6], Vector3.UP],
		[[0, 1, 3, 2], Vector3.FORWARD], [[4, 6, 7, 5], Vector3.BACK],
	]
	for f in faces:
		var idx: Array = f[0]
		var out: Vector3 = (basis * (f[1] as Vector3)).normalized()
		quad(c[idx[0]], c[idx[1]], c[idx[2]], c[idx[3]],
			u(0.02, 0.02), u(0.98, 0.02), u(0.98, 0.98), u(0.02, 0.98), out)

## Tapered spike -- claws, antler tines, teeth, fur spines.
func cone(base: Vector3, tip: Vector3, radius: float, sides: int = 4, base_close: bool = true) -> void:
	var axis := (tip - base)
	if axis.length() < 1e-6:
		return
	var t := axis.normalized()
	var ref := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var nx := (ref - t * ref.dot(t)).normalized()
	var ny := t.cross(nx).normalized()
	var pts := []
	for k in sides:
		var a := TAU * float(k) / float(sides)
		pts.append(base + (nx * cos(a) + ny * sin(a)) * radius)
	for k in sides:
		var k2 := (k + 1) % sides
		var mid := ((pts[k] as Vector3) + (pts[k2] as Vector3)) * 0.5
		tri(pts[k], pts[k2], tip,
			u(float(k) / float(sides), 1.0), u(float(k + 1) / float(sides), 1.0), u(0.5, 0.0),
			(mid - base).normalized() + t * 0.3)
	if base_close:
		_cap(pts, base, -t, 1.0)

## Double-sided flat card for fur tufts. Emitted both ways so a single
## back-face-culled material still shows the coat from every angle.
func card(root: Vector3, tip: Vector3, right: Vector3, width_root: float, width_tip: float) -> void:
	var a := root - right * width_root * 0.5
	var b := root + right * width_root * 0.5
	var c := tip + right * width_tip * 0.5
	var d := tip - right * width_tip * 0.5
	var nrm := (tip - root).cross(right).normalized()
	quad(a, b, c, d, u(0, 1), u(1, 1), u(1, 0), u(0, 0), nrm)
	quad(a, d, c, b, u(0, 1), u(0, 0), u(1, 0), u(1, 1), -nrm)

## Flat single quad (eyes, wound decals) facing `outward`.
func plane(centre: Vector3, right: Vector3, up: Vector3, outward: Vector3) -> void:
	quad(centre - right - up, centre + right - up, centre + right + up, centre - right + up,
		u(0, 1), u(1, 1), u(1, 0), u(0, 0), outward)

# ----------------------------------------------------------------- commit

func commit(mat: Material) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v_pos
	arr[Mesh.ARRAY_NORMAL] = v_nrm
	arr[Mesh.ARRAY_TEX_UV] = v_uv
	arr[Mesh.ARRAY_COLOR] = v_col
	arr[Mesh.ARRAY_BONES] = v_bone
	arr[Mesh.ARRAY_WEIGHTS] = v_wt
	var idx := PackedInt32Array()
	idx.resize(v_pos.size())
	for i in v_pos.size():
		idx[i] = i
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mat:
		m.surface_set_material(0, mat)
	return m
