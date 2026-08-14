extends RigidBody3D

var animal_name: String = "Deer2"
var score_value: int = 5000

func _ready():
	var pickup_area = Area3D.new()
	pickup_area.collision_layer = 0
	# Mask 15 covers layers 1, 2, 3, 4
	pickup_area.collision_mask = 15 
	
	var pickup_shape = CollisionShape3D.new()
	var pickup_box = BoxShape3D.new()
	pickup_box.size = Vector3(4.0, 4.0, 4.5) 
	pickup_shape.shape = pickup_box
	
	pickup_area.add_child(pickup_shape)
	add_child(pickup_area)
	
	pickup_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if body.is_in_group("player") or body.name == "Player":
		if body.has_method("pickup_animal") and not body.get("is_carrying_carcass"):
			body.pickup_animal(animal_name, score_value)
			var label = body.get_node_or_null("HUD/InteractionLabel")
			if label:
				label.text = "Carrying carcass. Return to the tarp."
			queue_free()
