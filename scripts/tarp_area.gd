extends Area3D

var cinematic_triggered = false

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	
	# Ensure the CinematicCamera is not current by default
	if has_node("CinematicCamera"):
		$CinematicCamera.current = false
		
	if has_node("Subtitles/SubtitleLabel"):
		$Subtitles/SubtitleLabel.text = ""

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
		if has_node("CinematicCamera"):
			$CinematicCamera.current = true
			
		# Play Animation
		if has_node("CinematicAnim"):
			$CinematicAnim.play("forest_encounter")
			
		# Wait for him to step out (3 seconds)
		await get_tree().create_timer(3.0).timeout
		
		# Show subtitles
		var score = 0
		if get_node_or_null("/root/GameManager"):
			score = get_node("/root/GameManager").drachmas
			
		if has_node("Subtitles/SubtitleLabel"):
			$Subtitles/SubtitleLabel.text = "That's excellent. Here is %d ₯. And here is the cash... You know, I will give you 10.000 ₯ for every young you bring to me." % score
			
		# Wait for dialogue and animation to finish
		await get_tree().create_timer(6.0).timeout
		
		get_tree().change_scene_to_file("res://scenes/NextLevel.tscn")
