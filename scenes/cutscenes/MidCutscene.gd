extends Node3D

@onready var suited_man = $SuitedMan
@onready var subtitle_label = $Subtitles/SubtitleLabel
@onready var fade_rect = $Subtitles/FadeRect

var transitioning = false
var skipping = false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var body_anim = suited_man.get_node_or_null("AnimationPlayer") if suited_man else null
	if body_anim and body_anim.has_animation("RESET"):
		body_anim.play("RESET")
		body_anim.stop()
	_run_sequence()

func _unhandled_input(event):
	if transitioning:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_select") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		skipping = true
		_transition_to_level2()

func _say(text: String, duration: float) -> bool:
	# typewriter_subtitle.gd on subtitle_label drives SuitedMan's lip-sync
	# automatically whenever .text changes (see scripts/typewriter_subtitle.gd).
	if subtitle_label:
		subtitle_label.text = text
	await get_tree().create_timer(duration).timeout
	if subtitle_label:
		subtitle_label.text = ""
	if skipping:
		return true
	await get_tree().create_timer(0.4).timeout
	return skipping

func _run_sequence():
	await get_tree().create_timer(1.0).timeout
	if skipping: return

	if await _say("So. You made it back in one piece.", 3.0): return
	if skipping: return

	var gm = get_node_or_null("/root/GameManager")
	var score = gm.drachmas if gm else 0
	if await _say("Here is your %d ₯, as agreed." % score, 3.2): return
	if skipping: return

	if await _say("Good, honest meat. The mountain provides.", 3.0): return
	if skipping: return

	_play_point_gesture()
	if await _say("But I need more. Go past the old road, to the wooden park by the mountain...", 4.2): return
	if skipping: return

	if await _say("...and the ruin beyond it. There is more waiting for you there.", 3.8): return
	if skipping: return

	if await _say("Do not disappoint me.", 2.5): return
	if skipping: return

	_transition_to_level2()

func _play_point_gesture():
	if not suited_man:
		return
	var shoulder = suited_man.get_node_or_null("RightShoulderPivot")
	var elbow = suited_man.get_node_or_null("RightShoulderPivot/RightUpperArm/RightElbowPivot")
	if shoulder:
		var tween = create_tween()
		tween.tween_property(shoulder, "rotation", Vector3(-0.3, -0.9, 0.1), 1.0)
	if elbow:
		var tween2 = create_tween()
		tween2.tween_property(elbow, "rotation", Vector3(-0.2, 0, 0), 1.0)

func _transition_to_level2():
	if transitioning:
		return
	transitioning = true
	if fade_rect:
		fade_rect.visible = true
		var tween = create_tween()
		tween.tween_property(fade_rect, "modulate:a", 1.0, 0.6)
		await tween.finished
	var gm = get_node_or_null("/root/GameManager")
	if gm and "level" in gm:
		gm.level = 2
	get_tree().change_scene_to_file("res://scenes/levels/Level2.tscn")
