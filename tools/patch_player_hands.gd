extends MainLoop
## Instances PlayerHands.tscn into Player.tscn under the weapon pivot, as a
## SIBLING of WWIRifle -- never a child of it, and nothing in this script
## touches WWIRifle or its children. The hands stay a fully separate model
## the gun knows nothing about, so they can be repositioned or given their
## own AnimationPlayer later without any risk to the rifle.
##
##   godot --headless --path . --script res://tools/patch_player_hands.gd
##
## Re-packs the existing scene rather than rewriting it by hand. Idempotent:
## rerunning it replaces the existing PlayerHands instance rather than
## duplicating it.

const PLAYER := "res://scenes/characters/Player.tscn"
const KEEP_UID := "uid://df721245"
const HANDS_SCENE := "res://scenes/characters/PlayerHands.tscn"

func _initialize() -> void:
	var ps: PackedScene = load(PLAYER)
	var root := ps.instantiate()
	# Persisted explicitly: the skinwalker AI finds the player by this group,
	# and a re-pack must not drop it.
	root.add_to_group("player", true)

	var pivot: Node3D = root.get_node("Head/Camera3D/WeaponPivot")

	# Sanity check the rifle is exactly where patch_player.gd left it --
	# this script must never disturb it.
	var rifle: Node3D = pivot.get_node("WWIRifle")
	assert(rifle.position == Vector3.ZERO and rifle.rotation == Vector3.ZERO,
		"WWIRifle moved from origin -- refusing to touch the scene")

	if pivot.has_node("PlayerHands"):
		var old := pivot.get_node("PlayerHands")
		pivot.remove_child(old)
		old.free()

	var hands: Node3D = load(HANDS_SCENE).instantiate()
	hands.name = "PlayerHands"
	hands.position = Vector3.ZERO
	pivot.add_child(hands)
	hands.owner = root

	_set_owner(root, root)
	var out := PackedScene.new()
	out.pack(root)
	var err := ResourceSaver.save(out, PLAYER)
	root.free()
	if err != OK:
		push_error("save failed: %d" % err)
		return
	_restore_uid(PLAYER, KEEP_UID)
	print("PATCH_PLAYER_HANDS_DONE")

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
