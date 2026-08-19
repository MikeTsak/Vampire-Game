extends Node3D
## Verifies the skinwalker only wakes on the armed level, and only once the
## player is physically inside the Park of Souls.
##
##   SW_LEVEL=2 LEVEL_PATH=res://scenes/levels/Level2.tscn godot --path . res://scenes/dev/SkinwalkerTest.tscn

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(640, 480))
	call_deferred("_run")

func _run() -> void:
	var lvl := int(OS.get_environment("SW_LEVEL"))
	if lvl == 0:
		lvl = 2
	var path := OS.get_environment("LEVEL_PATH")
	if path == "":
		path = "res://scenes/levels/Level2.tscn"

	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.level = lvl
	print("--- %s  (GameManager.level=%d) ---" % [path.get_file(), lvl])

	var level: Node = load(path).instantiate()
	add_child(level)
	await get_tree().create_timer(3.0).timeout
	# The level declares its own number now, so read back what it actually set
	# rather than trusting the value we seeded.
	var effective: int = gm.level if gm != null else -1
	print("effective GameManager.level after load = %d" % effective)

	var sw := level.find_child("skinwalker_new", true, false)
	if sw == null:
		sw = level.find_child("Skinwalker", true, false)
	if sw == null:
		print("no skinwalker in this level"); get_tree().quit(); return

	var park := level.find_child("ParkOfSouls", true, false)
	var trigger = park.find_child("ParkTrigger", true, false) if park else null
	print("park present=%s  trigger present=%s" % [park != null, trigger != null])
	print("A. after 3s idle      -> active=%s   (expected false)" % sw.active)

	if OS.get_environment("SW_DEBUG_FORCE") == "1":
		sw.debug_force_activate = true
		await get_tree().create_timer(0.6).timeout
		var lbl = sw.debug_label
		print("C. debug_force_activate -> active=%s  label=%s" % [
			sw.active, "\"%s\"" % (lbl.text if lbl else "<none>")])
		get_tree().quit()
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		print("no player found"); get_tree().quit(); return

	# Park it well outside first, then walk it into the middle of the statues.
	if park:
		var target: Vector3 = (park as Node3D).global_position
		player.global_position = target + Vector3(0, 1.5, 0)
		print("moved player into the park at %v" % target)
	await get_tree().create_timer(1.2).timeout
	print("B. standing in park   -> active=%s   (expected %s)" % [
		sw.active, "true" if effective == 2 else "false"])

	get_tree().quit()
