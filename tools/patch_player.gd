extends MainLoop
## Rebuilds the weapon rig inside Player.tscn: iron sights, muzzle flash, the
## audio players player.gd already expects, and a clean animation set.
##
##   godot --headless --path . --script res://tools/patch_player.gd
##
## Re-packs the existing scene rather than rewriting it by hand, so nothing
## outside the weapon and audio nodes is disturbed.

const PLAYER := "res://scenes/characters/Player.tscn"
const KEEP_UID := "uid://df721245"

## Bore exit in rifle-local space. Barrel is a 1.0-long cylinder centred at
## z -0.0607, so it ends here.
const MUZZLE := Vector3(0, 0.03, -0.57)
## Height of the sight line above the rifle origin. player.gd puts the weapon
## pivot at -this when aiming, which drops the sights onto screen centre.
const SIGHT_Y := 0.070
const BOLT_HOME := Vector3(0.03, 0.03, 0.4393)

func _initialize() -> void:
	var ps: PackedScene = load(PLAYER)
	var root := ps.instantiate()
	# Persisted explicitly: the skinwalker AI finds the player by this group,
	# and a re-pack must not drop it.
	root.add_to_group("player", true)

	var rifle: Node3D = root.get_node("Head/Camera3D/WeaponPivot/WWIRifle")
	# The rifle sat at an offset while the pivot ALSO carried one, and the
	# animations keyed absolute positions on top. Zeroing it makes the pivot the
	# single owner of where the gun is, so ADS and recoil can compose.
	rifle.position = Vector3.ZERO
	rifle.rotation = Vector3.ZERO

	_add_sights(rifle, root)
	_add_muzzle(rifle, root)
	_add_audio(root)
	_rebuild_anims(root)

	_set_owner(root, root)
	var out := PackedScene.new()
	out.pack(root)
	var err := ResourceSaver.save(out, PLAYER)
	root.free()
	if err != OK:
		push_error("save failed: %d" % err)
		return
	_restore_uid(PLAYER, KEEP_UID)
	print("PATCH_PLAYER_DONE")

# ------------------------------------------------------------------- pieces

## Front post and a rear notch, so there is something to actually line up when
## aiming. The rifle had no sights at all before.
func _add_sights(rifle: Node3D, own: Node) -> void:
	# Reuse the barrel's own material so the sights match the rest of the gun.
	var metal: Material = null
	if rifle.has_node("Barrel"):
		metal = (rifle.get_node("Barrel") as GeometryInstance3D).material_override
	var posts := [
		["FrontSight", Vector3(0, SIGHT_Y - 0.008, -0.50), Vector3(0.008, 0.030, 0.012)],
		# Rear notch sits forward on the barrel, not back on the receiver. With it
		# at the receiver, aligning the sights put the buttstock on the camera and
		# the grip filled half the screen. Barrel-mounted rear sights are also
		# period-correct for a WWI service rifle.
		["RearSightL", Vector3(-0.011, SIGHT_Y - 0.004, 0.02), Vector3(0.008, 0.020, 0.012)],
		["RearSightR", Vector3(0.011, SIGHT_Y - 0.004, 0.02), Vector3(0.008, 0.020, 0.012)],
	]
	for p in posts:
		if rifle.has_node(String(p[0])):
			continue
		var b := CSGBox3D.new()
		b.name = String(p[0])
		b.position = p[1]
		b.size = p[2]
		if metal:
			b.material_override = metal
		rifle.add_child(b)

## Marker at the bore plus the flash scene, so gameplay code has one place to
## aim tracers/impacts from and one node to trigger.
func _add_muzzle(rifle: Node3D, own: Node) -> void:
	if not rifle.has_node("Muzzle"):
		var mk := Node3D.new()
		mk.name = "Muzzle"
		mk.position = MUZZLE
		rifle.add_child(mk)
	var mk2: Node3D = rifle.get_node("Muzzle")
	if not mk2.has_node("MuzzleFlash"):
		var fl: Node = load("res://scenes/props/MuzzleFlash.tscn").instantiate()
		fl.name = "MuzzleFlash"
		mk2.add_child(fl)

## player.gd reads $GunSound and $FootstepSound; neither node existed, so no
## weapon or footstep audio had ever been heard.
func _add_audio(root: Node) -> void:
	# The synthetic sub-bass layer is gone: the supplied recording carries its
	# own low end, and its wav is no longer in the project.
	if root.has_node("GunBodySound"):
		var dead := root.get_node("GunBodySound")
		root.remove_child(dead)
		dead.free()
	var want := [
		["GunSound", "res://audio/gunshot.wav", 0.0],
		["FootstepSound", "res://audio/footstep.wav", -6.0],
	]
	for w in want:
		var p: AudioStreamPlayer
		if root.has_node(String(w[0])):
			p = root.get_node(String(w[0]))
		else:
			p = AudioStreamPlayer.new()
			p.name = String(w[0])
			root.add_child(p)
		# Always (re)assign: on a first pass the wav may not be imported yet.
		var stream = load(String(w[1]))
		if stream == null:
			push_warning("stream not importable yet: %s" % w[1])
		else:
			p.stream = stream
		p.volume_db = float(w[2])

func _set_owner(n: Node, own: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = own
		# Do not walk into instanced sub-scenes; their internals stay packed.
		if c.scene_file_path == "":
			_set_owner(c, own)

func _restore_uid(path: String, uid: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	if header.contains("uid="):
		var rx := RegEx.new()
		rx.compile('uid="[^"]+"')
		header = rx.sub(header, 'uid="%s"' % uid)
	else:
		header = header.trim_suffix("]") + ' uid="%s"]' % uid
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(header + text.substr(nl))
	f.close()

func _process(_d: float) -> bool:
	return true

# --------------------------------------------------------------- animations

func _track(a: Animation, path: String, times: Array, values: Array, interp: int) -> void:
	var ti := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ti, NodePath(path))
	a.track_set_interpolation_type(ti, interp)
	for i in times.size():
		a.track_insert_key(ti, float(times[i]), values[i])

## Rebuilt so nothing keys the rifle's ABSOLUTE position any more. Recoil is
## procedural in player.gd, and these only add sway, bob and the bolt cycle --
## all relative to a rifle sitting at the origin of the weapon pivot.
func _rebuild_anims(root: Node) -> void:
	var lin := Animation.INTERPOLATION_LINEAR
	var cub := Animation.INTERPOLATION_CUBIC
	var lib := AnimationLibrary.new()

	# Breathing sway while stood still.
	var idle := Animation.new()
	idle.length = 4.0
	idle.loop_mode = Animation.LOOP_LINEAR
	_track(idle, "WWIRifle:position", [0.0, 1.3, 2.6, 4.0], [
		Vector3(0, 0, 0), Vector3(0.003, -0.005, 0.0),
		Vector3(-0.002, 0.003, 0.002), Vector3(0, 0, 0)], cub)
	_track(idle, "WWIRifle:rotation", [0.0, 1.3, 2.6, 4.0], [
		Vector3(0, 0, 0), Vector3(0.010, 0.006, 0.0),
		Vector3(-0.006, -0.008, 0.004), Vector3(0, 0, 0)], cub)
	lib.add_animation("idle", idle)

	# Walk bob: a figure-eight so it does not read as a straight bounce.
	var bob := Animation.new()
	bob.length = 0.9
	bob.loop_mode = Animation.LOOP_LINEAR
	_track(bob, "WWIRifle:position", [0.0, 0.225, 0.45, 0.675, 0.9], [
		Vector3(0, 0, 0), Vector3(0.016, -0.012, 0), Vector3(0, 0.004, 0),
		Vector3(-0.016, -0.012, 0), Vector3(0, 0, 0)], cub)
	_track(bob, "WWIRifle:rotation", [0.0, 0.45, 0.9], [
		Vector3(0, 0, 0.020), Vector3(0, 0, -0.020), Vector3(0, 0, 0.020)], cub)
	lib.add_animation("walk_bob", bob)

	# Bolt cycle only -- the kick itself is code-driven.
	var shoot := Animation.new()
	shoot.length = 0.55
	_track(shoot, "WWIRifle/Bolt:rotation", [0.0, 0.10, 0.34, 0.46], [
		Vector3(0, 0, 0), Vector3(0, 0, 0.90), Vector3(0, 0, 0.90), Vector3(0, 0, 0)], lin)
	_track(shoot, "WWIRifle/Bolt:position", [0.0, 0.12, 0.22, 0.34, 0.46], [
		BOLT_HOME, BOLT_HOME, BOLT_HOME + Vector3(0, 0, 0.10),
		BOLT_HOME + Vector3(0, 0, 0.10), BOLT_HOME], lin)
	lib.add_animation("shoot", shoot)

	# Reload: tip the rifle in, work the bolt, bring it back on target.
	var reload := Animation.new()
	reload.length = 1.6
	# Deliberately NO WWIRifle position/rotation tracks here. Shouldered, the
	# receiver sits centimetres from the lens, so any body motion baked into the
	# clip punches through the near plane. player.gd applies that sway
	# procedurally instead, faded out by how far into the sights the player is.
	_track(reload, "WWIRifle/Bolt:rotation", [0.0, 0.35, 1.05, 1.30], [
		Vector3(0, 0, 0), Vector3(0, 0, 0.90), Vector3(0, 0, 0.90), Vector3(0, 0, 0)], lin)
	_track(reload, "WWIRifle/Bolt:position", [0.0, 0.40, 0.60, 1.00, 1.25], [
		BOLT_HOME, BOLT_HOME, BOLT_HOME + Vector3(0, 0, 0.11),
		BOLT_HOME + Vector3(0, 0, 0.11), BOLT_HOME], lin)
	lib.add_animation("reload", reload)

	var ap: AnimationPlayer = root.get_node("Head/Camera3D/WeaponPivot/AnimationPlayer")
	for name in ap.get_animation_library_list():
		ap.remove_animation_library(name)
	ap.add_animation_library("", lib)
	ap.autoplay = "idle"
