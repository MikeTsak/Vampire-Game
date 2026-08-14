extends Area3D

var cinematic_triggered = false
var skipping = false

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	
	if get_node_or_null("../CinematicCamera"):
		$"../CinematicCamera".current = false
		
	if get_node_or_null("../Subtitles/SubtitleLabel"):
		$"../Subtitles/SubtitleLabel".text = ""

func _unhandled_input(event):
	if cinematic_triggered and not skipping:
		if event.is_action_pressed("ui_accept"):
			skipping = true
			if GameManager and "level" in GameManager:
				GameManager.level = 2
			get_tree().change_scene_to_file("res://scenes/Level2.tscn")

func _on_body_entered(body):
	if cinematic_triggered: return
	if body.name == "Player" or body.is_in_group("player"):
		cinematic_triggered = true
		
		# Freeze player
		body.set_physics_process(false)
		body.set_process_input(false)
		
		# Hide HUD
		var hud = body.get_node_or_null("HUD")
		if hud: hud.visible = false
			
		var timer = get_node_or_null("../LevelTimer")
		if timer: timer.stop()
		
		# Switch Camera
		if get_node_or_null("../CinematicCamera"):
			$"../CinematicCamera".current = true
			
		var suited_man = get_node_or_null("../SuitedMan")
		var anim_player = null
		if suited_man:
			anim_player = suited_man.get_node_or_null("AnimationPlayer")
			if anim_player:
				anim_player.play("level1_ending")
		
		# Phase 1: Wait for him to step out (3 seconds)
		await get_tree().create_timer(3.0).timeout
		if skipping: return
		
		var final_score = 0
		if get_node_or_null("/root/GameManager"):
			final_score = get_node("/root/GameManager").drachmas
			
		# Phase 2: The Offer and Dialogue 1
		if get_node_or_null("../Subtitles/SubtitleLabel"):
			$"../Subtitles/SubtitleLabel".text = "That's excellent. Here is " + str(final_score) + " ₯. And here is the cash..."
			
		# Wait for dialogue 1 to finish (3.0 seconds)
		await get_tree().create_timer(3.0).timeout
		if skipping: return
		
		# Phase 3: The Turn at 6.0s. Detach Cash Prop.
		if suited_man:
			var cash = suited_man.get_node_or_null("RightShoulderPivot/RightUpperArm/RightElbowPivot/RightForearm/RightHand/CashProp")
			var tarp = get_node_or_null("../PhysicalTarp")
			if cash and tarp:
				var cache_global_transform = cash.global_transform
				cash.get_parent().remove_child(cash)
				tarp.add_child(cash)
				cash.global_transform = cache_global_transform
				cash.global_position.y -= 0.1 # Drop it slightly to rest on the tarp
		
		# Wait for Turn (1.0s) and Look Back (1.0s)
		await get_tree().create_timer(2.0).timeout
		if skipping: return
		
		# Phase 4: Look back and Dialogue 2
		if get_node_or_null("../Subtitles/SubtitleLabel"):
			$"../Subtitles/SubtitleLabel".text = "You know, I will give you 10.000 ₯ for every young one you bring to me."
			
		# Wait exactly 3 seconds for the player to read the final line and the man to turn
		await get_tree().create_timer(3.0).timeout
		
		# Increment the level index (if your GameManager uses one) to ensure Level 2 spawns correctly
		if GameManager and "level" in GameManager:
			GameManager.level = 2
			
		# Force the transition immediately
		get_tree().change_scene_to_file("res://scenes/Level2.tscn")
