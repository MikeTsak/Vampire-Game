extends Node3D
## Dev stage: drops one carcass of every species through the real
## carcass_zone.spawn_tarp_carcass path and lets physics settle them, so how a
## dead animal actually comes to rest can be checked without hunting one down.

## The generated animals, plus the two legacy CSG ones -- carcass_pose is
## shared code, so the old models have to keep working through it too.
const NAMES := ["deer_new", "sheep_new", "boar_new",
	"baby_deer_new", "baby_sheep_new", "baby_boar_new",
	"Deer2", "Sheep2"]
const CarcassPose = preload("res://scripts/carcass_pose.gd")

func _ready() -> void:
	for i in NAMES.size():
		var carcass := RigidBody3D.new()
		carcass.add_to_group("tarp_carcass")
		carcass.set_meta("animal_name", NAMES[i])

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 1.0, 1.5)
		shape.shape = box
		carcass.add_child(shape)

		var scene := load("res://scenes/animals/%s.tscn" % NAMES[i])
		if scene:
			var inst = scene.instantiate()
			var mesh = inst.get_node_or_null("MeshBase")
			if mesh:
				inst.remove_child(mesh)
				mesh.owner = null
				carcass.add_child(mesh)
				var fitted = CarcassPose.lay_down(mesh)
				if fitted != Vector3.ZERO:
					box.size = fitted
			inst.queue_free()

		add_child(carcass)
		carcass.global_position = Vector3(i * 2.1 - 7.35, 0.9, 0.0)
