extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.name == "Player" or body.is_in_group("player"):
		body.is_on_tarp = true

func _on_body_exited(body: Node3D) -> void:
	if body.name == "Player" or body.is_in_group("player"):
		body.is_on_tarp = false
