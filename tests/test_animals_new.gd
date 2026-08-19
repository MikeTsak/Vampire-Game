extends SceneTree
## Functional test for the generated `_new` animals: they wander, they pick the
## right clip while doing it, and shooting one leaves a carcass the rest of the
## game can pick up.
##
## Run headless:
##   godot --headless --path <project> --script res://tests/test_animals_new.gd

const MANIFEST := "res://models/animals/animals_new.json"
const CarcassPose = preload("res://scripts/carcass_pose.gd")

var entries: Array = []
var animals: Array[Node] = []
var stage: Node3D
var failures: Array[String] = []
var elapsed := 0.0
var phase := 0
var moved_at_least_once := {}

func _initialize() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	entries = JSON.parse_string(f.get_as_text())
	f.close()

	stage = Node3D.new()
	stage.name = "Stage"
	root.add_child(stage)
	# animal.gd parents the carcass to the current scene, so there has to be one
	current_scene = stage

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	floor_shape.shape = box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)

	for i in entries.size():
		var inst := (load(entries[i]["scene"]) as PackedScene).instantiate()
		inst.position = Vector3(i * 6.0 - 15.0, 0.15, 0.0)
		stage.add_child(inst)
		animals.append(inst)
		moved_at_least_once[entries[i]["name"]] = false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

func _process(delta: float) -> bool:
	elapsed += delta

	# ── phase 0: let them wander, watch which clip they choose ─────────────
	if phase == 0:
		for i in animals.size():
			var a: Node = animals[i]
			if not is_instance_valid(a):
				continue
			var ap := a.get_node_or_null("MeshBase/AnimationPlayer") as AnimationPlayer
			if ap == null or not ap.is_playing():
				continue
			var clip := ap.current_animation
			_check(clip in ["idle", "walk"],
				"%s plays '%s' while alive" % [entries[i]["name"], clip])
			if clip == "walk":
				moved_at_least_once[entries[i]["name"]] = true

		if elapsed > 2.5:
			for i in animals.size():
				var a: Node = animals[i]
				_check(a.is_in_group("animals"),
					"%s is not in the animals group" % entries[i]["name"])
				_check(not a.get("dead"),
					"%s died on its own" % entries[i]["name"])
				a.die()
			phase = 1
			elapsed = 0.0
		return false

	# ── phase 1: give every death clip time to play out, then look for bodies
	if phase == 1:
		if elapsed < 4.0:
			return false
		var carcasses := get_nodes_in_group("carcass")
		_check(carcasses.size() == entries.size(),
			"%d carcasses for %d animals" % [carcasses.size(), entries.size()])

		var by_name := {}
		for c in carcasses:
			by_name[c.get_meta("animal_name", "")] = c
		for e in entries:
			var name: String = e["name"]
			if not _has(by_name, name):
				failures.append("no carcass named '%s'" % name)
				continue
			var c: Node = by_name[name]
			_check(c is RigidBody3D, "%s carcass is not a RigidBody3D" % name)
			_check(int(c.get("score_value")) == int(e["score_value"]),
				"%s carcass scores %s, expected %d"
					% [name, str(c.get("score_value")), e["score_value"]])
			# the visual rig has to travel with the body, or the player picks
			# up an invisible animal
			_check(c.get_node_or_null("MeshBase/Skeleton3D") != null,
				"%s carcass lost its skeleton" % name)

			# The lie-down rotates MeshBase about the animal's feet, so without
			# re-centring the body swings out sideways and sinks through the
			# floor. Guard both: the visual must sit on its own collision box.
			var mb := c.get_node_or_null("MeshBase") as Node3D
			if mb != null:
				var box := CarcassPose.visual_bounds(mb)
				var off: float = box.get_center().length()
				_check(off < 0.15,
					"%s carcass visual sits %.2f m off its own body" % [name, off])
				var col := _first_box(c)
				if col != Vector3.ZERO:
					_check((col - box.size).length() < 0.05,
						"%s collision box is %s but the body is %s"
							% [name, str(col), str(box.size)])
			# and the scene the pickup code reloads by that name must exist
			_check(ResourceLoader.exists("res://scenes/animals/%s.tscn" % name),
				"%s has no scene for carcass_zone to reload" % name)

		for a in animals:
			_check(not is_instance_valid(a),
				"an animal outlived its own death")

		var walkers := 0
		for k in moved_at_least_once:
			if moved_at_least_once[k]:
				walkers += 1
		_check(walkers >= 3,
			"only %d of %d animals ever chose the walk clip"
				% [walkers, entries.size()])

		print("test_animals_new: %d animals, %d carcasses, %d seen walking"
			% [entries.size(), carcasses.size(), walkers])
		if failures.is_empty():
			print("PASS")
			quit(0)
		else:
			print("FAIL (%d):" % failures.size())
			for m in failures:
				print("  - ", m)
			quit(1)
	return false

## Size of the carcass body's collision box, or zero if it has none.
func _first_box(body: Node) -> Vector3:
	for ch in body.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
			return ((ch as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ZERO

func _has(d: Dictionary, k: String) -> bool:
	return d.has(k) and d[k] != null
