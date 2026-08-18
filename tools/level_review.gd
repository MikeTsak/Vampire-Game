extends Node3D
## Loads a level as a running game, waits for procedural generation to settle,
## then reports what actually got built and grabs an overhead shot.
##
## Answers the review questions with measurements rather than assumptions:
## does the fence collide, do the trees reach the map edge, and is the Park of
## Souls really on the far side from the sanatorium.

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(900, 900))
	call_deferred("_run")

func _run() -> void:
	var dir := OS.get_environment("LEVEL_SHOT_DIR")
	if dir == "" :
		dir = "res://"
	elif not dir.ends_with("/"):
		dir += "/"
	var level_path := OS.get_environment("LEVEL_PATH")
	if level_path == "":
		level_path = "res://scenes/levels/Level2.tscn"

	var level: Node = load(level_path).instantiate()
	add_child(level)
	# Forest/terrain generation runs over the first frames; give it real time.
	await get_tree().create_timer(3.0).timeout

	print("--- %s ---" % level_path.get_file())
	_report_counts(level)
	_report_park(level)
	await _report_fence(level)
	await _overhead(level, dir)
	get_tree().quit()

func _report_counts(level: Node) -> void:
	var trees := 0
	var rocks := 0
	var animals := 0
	var minx := 1e9
	var maxx := -1e9
	var minz := 1e9
	var maxz := -1e9
	var stack: Array = [level]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var nm := String(n.name)
		if nm.begins_with("FirTree") or nm.begins_with("PineTree") or nm.begins_with("Platanus") or nm.begins_with("@"):
			trees += 1
			if n is Node3D:
				var p := (n as Node3D).position
				minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
				minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
		elif nm.begins_with("Rock"):
			rocks += 1
		elif nm.begins_with("Deer") or nm.begins_with("Sheep") or nm.begins_with("Baby"):
			animals += 1
	var fg := level.find_child("ForestGenerator", true, false)
	if fg:
		print("ForestGenerator children=%d" % fg.get_child_count())
	print("trees=%d  rocks=%d  animals=%d" % [trees, rocks, animals])
	if trees > 0:
		print("tree spread: x %.0f..%.0f   z %.0f..%.0f" % [minx, maxx, minz, maxz])
	print("Tarp count=%d  OilLamp count=%d" % [
		_count_named(level, "Tarp"), _count_named(level, "OilLamp")])

func _count_named(root: Node, prefix: String) -> int:
	var c := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if String(n.name).begins_with(prefix):
			c += 1
	return c

func _report_park(level: Node) -> void:
	var park := level.find_child("ParkOfSouls", true, false)
	var sana := level.find_child("SanatoriumBuilding", true, false)
	if park == null:
		print("ParkOfSouls: MISSING")
		return
	var pp: Vector3 = (park as Node3D).global_position
	if sana:
		var sp: Vector3 = (sana as Node3D).global_position
		print("ParkOfSouls at %v | Sanatorium at %v | apart %.0fm" % [pp, sp, pp.distance_to(sp)])
	else:
		print("ParkOfSouls at %v (no sanatorium node found)" % pp)

## Fire rays across each fence run; a hit means the barrier is really there.
func _report_fence(level: Node) -> void:
	await get_tree().physics_frame
	var sana := level.find_child("SanatoriumBuilding", true, false)
	if sana == null:
		print("fence: no sanatorium in this level")
		return
	var base: Vector3 = (sana as Node3D).global_position
	var space := get_world_3d().direct_space_state
	var tests := {
		"front-left": [Vector3(-25, 2.5, 40), Vector3(-25, 2.5, 5)],
		"front-right": [Vector3(25, 2.5, 40), Vector3(25, 2.5, 5)],
		"left": [Vector3(-60, 2.5, 3), Vector3(-30, 2.5, 3)],
		"right": [Vector3(60, 2.5, 3), Vector3(30, 2.5, 3)],
		"back": [Vector3(0, 2.5, -35), Vector3(0, 2.5, -5)],
		"GATEWAY (should be open)": [Vector3(0, 2.5, 32), Vector3(0, 2.5, 14)],
	}
	for label in tests:
		var a: Vector3 = base + tests[label][0]
		var b: Vector3 = base + tests[label][1]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
		var who := ""
		if hit and hit.has("collider") and hit["collider"] != null:
			who = "  <- %s" % hit["collider"].name
		print("  fence %-26s %s%s" % [label, "BLOCKED" if hit else "open", who])
	# Sweep the gateway to find exactly where the opening is.
	var opening := []
	for xi in range(-14, 15, 2):
		var fa := base + Vector3(float(xi), 2.5, 32)
		var fb := base + Vector3(float(xi), 2.5, 14)
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(fa, fb)).is_empty():
			opening.append(xi)
	print("  gateway clear at x = %s" % str(opening))

func _overhead(level: Node, dir: String) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 340.0
	cam.far = 900.0
	cam.position = Vector3(0, 300, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	add_child(cam)
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("overhead shot err=%d" % img.save_png(dir + "level_overhead.png"))
