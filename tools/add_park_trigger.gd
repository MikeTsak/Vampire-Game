extends MainLoop
## Adds a ParkTrigger Area3D to the Park of Souls.
##
##   godot --headless --path . --script res://tools/add_park_trigger.gd
##
## The skinwalker used to wake when the player came within 70m of the park,
## which is "somewhere nearby" rather than "inside it". A real trigger volume
## sized to the park's own footprint gives it an actual threshold to cross.
##
## Idempotent: an existing ParkTrigger is rebuilt.

const SCENE := "res://scenes/environment/ParkOfSouls.tscn"
## Statue and archway origins only bound the centres of the props, so pad out
## to cover the ground they actually stand on.
const PAD := 5.0
const TRIGGER_HEIGHT := 12.0

func _initialize() -> void:
	var root := (load(SCENE) as PackedScene).instantiate()

	var old := root.get_node_or_null("ParkTrigger")
	if old:
		root.remove_child(old)
		old.free()

	var minv := Vector3(1e9, 1e9, 1e9)
	var maxv := Vector3(-1e9, -1e9, -1e9)
	var found := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n != root and n is Node3D:
			var p := _to_root(n as Node3D, root).origin
			minv = minv.min(p)
			maxv = maxv.max(p)
			found += 1
	if found == 0:
		push_error("no Node3D children found")
		root.free()
		return

	var centre := (minv + maxv) * 0.5
	var size := (maxv - minv) + Vector3(PAD * 2.0, 0, PAD * 2.0)
	size.y = TRIGGER_HEIGHT
	print("park prop bounds: min=%v max=%v (%d nodes)" % [minv, maxv, found])
	print("trigger centre=%v size=%v" % [Vector3(centre.x, TRIGGER_HEIGHT * 0.5 - 2.0, centre.z), size])

	var area := Area3D.new()
	area.name = "ParkTrigger"
	# Layer 1 is where the player body sits; monitor only, never collide.
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	root.add_child(area)

	var cs := CollisionShape3D.new()
	cs.name = "Volume"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(centre.x, TRIGGER_HEIGHT * 0.5 - 2.0, centre.z)
	area.add_child(cs)

	area.owner = root
	cs.owner = root

	var out := PackedScene.new()
	out.pack(root)
	var err := ResourceSaver.save(out, SCENE)
	root.free()
	print("save err=%d" % err)
	print("PARK_TRIGGER_DONE")

func _to_root(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D()
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _process(_d: float) -> bool:
	return true
