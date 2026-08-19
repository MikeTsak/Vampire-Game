extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if "is_on_tarp" in body:
			body.is_on_tarp = true

		if body.get("is_carrying_carcass"):
			if body.has_method("drop_animal"):
				var dropped_name = body.drop_animal()
				if dropped_name != "":
					spawn_tarp_carcass(dropped_name)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		if "is_on_tarp" in body:
			body.is_on_tarp = false

## Builds one dropped carcass on the canvas and hands it to the level.
## Public because the F10 level skip fills the tarp through this same path --
## what the debug shortcut produces has to be the identical object the player
## would have carried in, group and all, or the ending has nothing to swap.
func spawn_tarp_carcass(animal_name: String, drop_height: float = 1.5) -> RigidBody3D:
	var carcass = RigidBody3D.new()
	# The ending sequence swaps exactly this group for human bodies, so only
	# what actually lands on the tarp is tagged.
	carcass.add_to_group("tarp_carcass")
	carcass.set_meta("animal_name", animal_name)

	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.5)
	shape.shape = box
	carcass.add_child(shape)

	var scene = load("res://scenes/animals/" + animal_name + ".tscn")
	if scene:
		var inst = scene.instantiate()
		var mesh = inst.get_node_or_null("MeshBase")
		if mesh:
			inst.remove_child(mesh)
			# Still owned by the animal scene it came out of; leaving that set
			# makes Godot warn on every single drop.
			mesh.owner = null
			carcass.add_child(mesh)
			mesh.position = Vector3.ZERO
			mesh.rotation.z = PI / 2
			mesh.rotation.x = PI
		inst.queue_free()

	carcass.collision_layer = 1
	carcass.collision_mask = 1

	get_tree().current_scene.add_child(carcass)
	# Spread the drops over the canvas instead of stacking them on one spot: a
	# scattered pile reads as a haul, and the ending inherits that scatter when
	# the bodies are swapped for people.
	carcass.global_position = self.global_position + Vector3(
		randf_range(-2.0, 2.0), drop_height, randf_range(-2.0, 2.0))
	carcass.rotation.y = randf_range(0.0, TAU)

	var level = get_tree().current_scene
	if level and level.has_method("on_carcass_dropped_on_tarp"):
		level.on_carcass_dropped_on_tarp(carcass)
	return carcass
