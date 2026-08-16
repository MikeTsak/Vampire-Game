extends Node3D

func _ready():
	$MainAnimation.play("intro_seq")
	_handle_lipsync()

func _handle_lipsync():
	# The typewriter script now handles lip-sync. Just wait for the end to pass the glass.
	await get_tree().create_timer(17.5).timeout
	slide_glass_to_player()

func slide_glass_to_player():
	var hand_glass = $SuitedMan.get_node_or_null("RightShoulderPivot/RightUpperArm/RightElbowPivot/RightForearm/RightHand/ManGlass")
	
	var glass_packed = load("res://scenes/props/DrinkGlass.tscn")
	var new_glass = glass_packed.instantiate()
	new_glass.name = "TweenGlass"
	add_child(new_glass)
	
	if hand_glass:
		new_glass.global_position = hand_glass.global_position
		new_glass.global_rotation = hand_glass.global_rotation
		hand_glass.hide()
	else:
		new_glass.global_position = $SuitedMan.global_position + Vector3(0.5, 0.5, 0.5)
	
	var camera = $Camera3D
	var target_pos = camera.global_position + camera.global_transform.basis.z * -0.6
	target_pos.y = camera.global_position.y - 0.25
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(new_glass, "global_position", target_pos, 1.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(new_glass, "rotation_degrees", Vector3(-20, 0, 0), 1.2).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_callback(transition_to_gameplay).set_delay(1.5)

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_select") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		transition_to_gameplay()

func transition_to_gameplay():
	get_tree().change_scene_to_file("res://scenes/levels/Level1.tscn")
