extends Area3D

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
    if body.is_in_group("carcass"):
        print("Carcass successfully dropped on the Tarp!")
        # Add score logic here, e.g., GameManager.add_score(1000)
