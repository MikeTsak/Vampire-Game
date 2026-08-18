extends Node
## Fires once, then samples the gun audio and the fire lock, so both the
## "sound never ends" and "can fire during reload" questions are answered concretely.

func _ready() -> void:
	# Gate at RUNTIME as well as at build time. This node gets packed into
	# GunTest.tscn when the scene is built with GUN_AUDIO_PROBE=1, and a
	# leftover probe hammering the trigger every 0.25s looks exactly like the
	# game re-firing on its own.
	if OS.get_environment("GUN_AUDIO_PROBE") != "1":
		queue_free()
		return
	var player: Node = get_tree().current_scene.get_node("Player")
	var gun: AudioStreamPlayer = player.get_node("GunSound")
	var st: AudioStreamWAV = gun.stream
	var fmt := {0: "8-bit", 1: "16-bit PCM", 2: "IMA-ADPCM", 3: "QOA (lossy)"}
	print("stream: %.2fs  %dHz  %s  loop_mode=%d (0=disabled)" % [
		st.get_length(), st.mix_rate, fmt.get(st.format, "?"), st.loop_mode])
	print("body node present: %s" % (player.get_node_or_null("GunBodySound") != null))
	var ap: AnimationPlayer = player.get_node("Head/Camera3D/WeaponPivot/AnimationPlayer")

	await get_tree().create_timer(0.4).timeout
	player.shoot()
	print("fired. reload clip = %.2fs" % ap.get_animation("reload").length)
	# Hammer the trigger throughout, to prove the lock actually holds.
	var blocked := 0
	for i in 14:
		await get_tree().create_timer(0.2).timeout
		if not player.can_shoot:
			blocked += 1
		player.shoot()   # should be a no-op until the reload finishes
		print("  t=%4.2fs  audio_playing=%-5s  can_shoot=%-5s  anim=%s" % [
			(i + 1) * 0.2, gun.playing, player.can_shoot, ap.current_animation])
	print("trigger pulls rejected while locked: %d" % blocked)
	get_tree().quit()
