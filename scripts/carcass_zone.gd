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
					var carcass = RigidBody3D.new()
					var shape = CollisionShape3D.new()
					var box = BoxShape3D.new()
					box.size = Vector3(1.0, 1.0, 1.5)
					shape.shape = box
					carcass.add_child(shape)
					
					var scene = load("res://scenes/animals/" + dropped_name + ".tscn")
					if scene:
						var inst = scene.instantiate()
						var mesh = inst.get_node_or_null("MeshBase")
						if mesh:
							inst.remove_child(mesh)
							carcass.add_child(mesh)
							mesh.position = Vector3.ZERO
							mesh.rotation.z = PI / 2
							mesh.rotation.x = PI
						inst.queue_free()
					
					carcass.collision_layer = 1
					carcass.collision_mask = 1
					
					get_tree().current_scene.add_child(carcass)
					carcass.global_position = self.global_position + Vector3(0, 1.5, 0)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		if "is_on_tarp" in body:
			body.is_on_tarp = false
