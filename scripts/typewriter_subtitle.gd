extends Label

var full_text = ""
var type_timer = 0.0
var type_speed = 0.03 # Fast typewriter

func _ready():
	# Label.visible_characters defaults to -1 ("show all"), not 0. Left alone,
	# the first _process() tick increments it to 0 and then indexes
	# full_text[-1] while full_text is still "", which crashes.
	visible_characters = 0

func _get_suited_man() -> Node:
	# Relative to self (SubtitleLabel -> Subtitles -> cutscene root -> SuitedMan) so this
	# still resolves when the cutscene is instanced inside another scene (e.g. live in a
	# level) rather than being get_tree().current_scene itself.
	var cutscene_root = get_parent().get_parent() if get_parent() else null
	if not cutscene_root:
		return null
	return cutscene_root.get_node_or_null("SuitedMan")

func _get_dialogue_blip() -> AudioStreamPlayer:
	# Climb up: SubtitleLabel -> Subtitles -> cutscene root -> DialogueBlip
	var cutscene_root = get_parent().get_parent() if get_parent() else null
	if not cutscene_root:
		return null
	return cutscene_root.get_node_or_null("DialogueBlip")

func _process(delta):
	if text != full_text:
		full_text = text
		visible_characters = 0
		type_timer = 0.0

		var sm = _get_suited_man()
		if sm and sm.has_method("start_talking") and full_text.length() > 0:
			sm.start_talking()
		elif sm and sm.has_method("stop_talking") and full_text.length() == 0:
			sm.stop_talking()

	if visible_characters < full_text.length():
		type_timer += delta
		if type_timer >= type_speed:
			type_timer -= type_speed
			visible_characters += 1

			# Play dialogue blip on every non-space character reveal (retro voice mumble)
			var ch = full_text[visible_characters - 1]
			if ch != " " and ch != "\n":
				var blip = _get_dialogue_blip()
				if blip:
					blip.pitch_scale = randf_range(0.85, 1.15)
					blip.play()

			if visible_characters >= full_text.length():
				var sm = _get_suited_man()
				if sm and sm.has_method("stop_talking"):
					sm.stop_talking()
