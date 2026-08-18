extends MainLoop
## Corrects the sanatorium fence collision.
##
##   godot --headless --path . --script res://tools/fix_fence_collision.gd
##
## The fence panels are plain MeshInstance3D, which makes it look as though the
## fence has no collision at all -- but a separate `FenceBlocker` StaticBody3D
## already carries a box per panel run. What was actually wrong is that it also
## carries `Collision_Gate`, a box straight across the gateway, so the entrance
## was sealed and the player could never get inside the grounds. Level 3 puts
## the tarp outside the gates and expects the player to hunt inside and carry
## loot out, which that box makes impossible.
##
## This disables the gate box (reversible, rather than deleting it) and removes
## the duplicate FenceCollision node an earlier pass of mine added before I
## spotted FenceBlocker. No visual geometry is touched.

const SCENE := "res://scenes/environment/SanatoriumBuilding_new.tscn"
const KEEP_UID := "uid://cvwws2y5id6wh"

func _initialize() -> void:
	var root := (load(SCENE) as PackedScene).instantiate()

	# Drop the duplicate barrier: FenceBlocker already covers every run.
	var dup := root.get_node_or_null("FenceCollision")
	if dup:
		root.remove_child(dup)
		dup.free()
		print("removed duplicate FenceCollision")

	var blocker := root.get_node_or_null("FenceBlocker")
	if blocker == null:
		push_error("FenceBlocker missing -- fence would have no collision at all")
		root.free()
		return

	var opened := false
	for c in blocker.get_children():
		if c is CollisionShape3D:
			var keep := String(c.name) != "Collision_Gate"
			(c as CollisionShape3D).disabled = not keep
			if not keep:
				opened = true
			print("  %-22s %s" % [c.name, "SOLID" if keep else "disabled (gateway)"])
	if not opened:
		push_warning("no Collision_Gate found; gateway may already be open")

	var out := PackedScene.new()
	out.pack(root)
	var err := ResourceSaver.save(out, SCENE)
	root.free()
	if err != OK:
		push_error("save failed %d" % err)
		return
	_restore_uid(SCENE, KEEP_UID)
	print("FENCE_DONE")

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
