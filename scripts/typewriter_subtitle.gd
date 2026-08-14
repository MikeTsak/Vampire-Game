extends Label

var full_text = ""
var type_timer = 0.0
var type_speed = 0.03 # Fast typewriter

func _process(delta):
	if text != full_text:
		full_text = text
		visible_characters = 0
		type_timer = 0.0
		
		var sm = get_tree().current_scene.get_node_or_null("SuitedMan")
		if sm and sm.has_method("start_talking") and full_text.length() > 0:
			sm.start_talking()
		
	if visible_characters < full_text.length():
		type_timer += delta
		if type_timer >= type_speed:
			type_timer -= type_speed
			visible_characters += 1
			
			if visible_characters >= full_text.length():
				var sm = get_tree().current_scene.get_node_or_null("SuitedMan")
				if sm and sm.has_method("stop_talking"):
					sm.stop_talking()
