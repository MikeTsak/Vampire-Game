extends Node3D

signal cutscene_finished

@onready var suited_man = $SuitedMan
@onready var subtitle_label = $Subtitles/SubtitleLabel
@onready var fade_rect = $Subtitles/FadeRect
@onready var sequence = $Sequence
@onready var coin_player = $CoinSfxPlayer

var finished = false

func _ready():
	var body_anim = suited_man.get_node_or_null("AnimationPlayer") if suited_man else null
	if body_anim and body_anim.has_animation("RESET"):
		body_anim.play("RESET")
		body_anim.stop()
	if sequence:
		sequence.animation_finished.connect(_on_sequence_finished)
		sequence.play("sequence")

func _unhandled_input(event):
	if finished:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_select") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		_finish()

func _on_sequence_finished(_anim_name: StringName):
	_finish()

func _set_model_state(state: String):
	if not suited_man:
		return
	var anim = suited_man.get_node_or_null("AnimationPlayer")
	if anim and anim.has_animation(state):
		anim.play(state)

func _set_subtitle(text: String):
	if subtitle_label:
		subtitle_label.text = text

func _show_payment():
	var gm = get_node_or_null("/root/GameManager")
	var payment = gm.drachmas if gm else 0
	_set_subtitle("Payment received: %d ₯" % payment)
	_play_coin_sfx()

func _play_coin_sfx():
	if not coin_player:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100.0
	gen.buffer_length = 0.6
	coin_player.stream = gen
	coin_player.play()
	var playback: AudioStreamGeneratorPlayback = coin_player.get_stream_playback()
	if not playback:
		return
	var sample_rate = gen.mix_rate
	var freqs = [1568.0, 2093.0, 2637.0, 3136.0]
	var total_frames = int(sample_rate * 0.5)
	for i in range(total_frames):
		var t = float(i) / sample_rate
		var sample = 0.0
		for j in range(freqs.size()):
			var start = j * 0.05
			if t >= start:
				var local_t = t - start
				var env = exp(-local_t * 10.0)
				sample += sin(TAU * freqs[j] * local_t) * env * 0.25
		playback.push_frame(Vector2(sample, sample))

func _finish():
	if finished:
		return
	finished = true
	if sequence:
		sequence.stop()
	_set_subtitle("")
	if fade_rect:
		fade_rect.visible = true
		var tween = create_tween()
		tween.tween_property(fade_rect, "modulate:a", 1.0, 0.8)
		await tween.finished
	cutscene_finished.emit()
