extends SceneTree

var frame = 0
var level
var player

func _initialize():
	var root = get_root()
	var packed = load("res://scenes/Level1.tscn")
	level = packed.instantiate()
	root.add_child(level)
	
func _process(delta) -> bool:
	frame += 1
	if frame == 10:
		player = level.get_node("Player")
		print("[AUTO] Dropping first animal...")
		player.is_carrying_animal = true
		player.carried_animal_name = "Deer2"
		player.carried_score_value = 5000
		level._on_drop_zone_body_entered(player)
		
	if frame == 20:
		print("[AUTO] Dropping second animal...")
		player.is_carrying_animal = true
		player.carried_animal_name = "Sheep2"
		player.carried_score_value = 5000
		level._on_drop_zone_body_entered(player)
		
	if frame == 30:
		var tarp = level.get_node("Tarp/MeshInstance3D")
		var dropzone = level.get_node("Tarp/CarcassDropZone/CollisionShape3D")
		var mesh = tarp.mesh
		print("[AUTO] Tarp Size: ", mesh.size)
		print("[AUTO] DropZone Size: ", dropzone.shape.size)
		
		var carcasses = get_root().get_tree().get_nodes_in_group("carcass")
		print("[AUTO] Carcasses dropped: ", carcasses.size())
		for c in carcasses:
			print("[AUTO] Carcass pos: ", c.global_position)
			
		print("[AUTO] VERIFICATION COMPLETE")
		quit()
		
	return false
