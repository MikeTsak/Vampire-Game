extends CharacterBody3D

const CarcassPose = preload("res://scripts/carcass_pose.gd")

const SPEED = 2.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var wander_timer: float = 0.0
var move_direction: Vector3 = Vector3.ZERO
var dead: bool = false
var time_alive: float = 0.0
@export var score_value: int = 5000

@onready var mesh_base = $MeshBase
@onready var legs = [
	get_node_or_null("MeshBase/Leg0"), get_node_or_null("MeshBase/Leg1"), get_node_or_null("MeshBase/Leg2"), get_node_or_null("MeshBase/Leg3")
]

# ── Audio nodes (created dynamically in _ready) ──────────────────
var hoof_sound: AudioStreamPlayer3D = null
var idle_sound: AudioStreamPlayer3D = null
var death_sound: AudioStreamPlayer3D = null

# ── Footstep timing ──────────────────────────────────────────────
var _hoof_timer: float = 0.0
const HOOF_INTERVAL: float = 0.38   # seconds between hoof steps

# ── Idle sound timing ────────────────────────────────────────────
var _idle_timer: float = 0.0

func _ready():
	add_to_group("animals")
	if "Baby" in name or "Baby" in scene_file_path:
		score_value = 10000
	randomize_wander()
	_setup_audio()
	_idle_timer = randf_range(3.0, 10.0)  # First idle sound after 3-10s

func _setup_audio():
	# Determine species from name/path for choosing idle sound
	var is_sheep = "Sheep" in name or "Sheep" in scene_file_path
	var idle_stream_path = "res://audio/sheep_bleat.wav" if is_sheep else "res://audio/deer_snort.wav"

	# ── HoofSteps ────────────────────────────────────────────────
	hoof_sound = AudioStreamPlayer3D.new()
	hoof_sound.name = "HoofSteps"
	hoof_sound.stream = load("res://audio/hoof_step.wav")
	hoof_sound.bus = &"RetroFilter"
	hoof_sound.volume_db = -3.0
	hoof_sound.max_distance = 25.0
	hoof_sound.unit_size = 5.0
	add_child(hoof_sound)

	# ── IdleSound ─────────────────────────────────────────────────
	idle_sound = AudioStreamPlayer3D.new()
	idle_sound.name = "IdleSound"
	idle_sound.stream = load(idle_stream_path)
	idle_sound.bus = &"RetroFilter"
	idle_sound.volume_db = 1.0
	idle_sound.max_distance = 40.0
	idle_sound.unit_size = 8.0
	add_child(idle_sound)

	# ── DeathSound ────────────────────────────────────────────────
	death_sound = AudioStreamPlayer3D.new()
	death_sound.name = "DeathSound"
	death_sound.stream = load("res://audio/animal_death.wav")
	death_sound.bus = &"RetroFilter"
	death_sound.volume_db = 4.0
	death_sound.max_distance = 50.0
	death_sound.unit_size = 10.0
	add_child(death_sound)

func randomize_wander():
	if dead: return
	move_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	wander_timer = randf_range(2.0, 5.0)

func _physics_process(delta):
	if dead:
		return
		
	if not is_on_floor():
		velocity.y -= gravity * delta

	wander_timer -= delta
	if wander_timer <= 0:
		randomize_wander()
		
	if move_direction != Vector3.ZERO:
		var target_rotation = atan2(-move_direction.x, -move_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, 5.0 * delta)

	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED

	move_and_slide()
	
	# ── Footstep Audio ───────────────────────────────────────────
	var horiz_speed = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz_speed > 0.5:
		_hoof_timer -= delta
		if _hoof_timer <= 0.0:
			_hoof_timer = HOOF_INTERVAL * (SPEED / max(horiz_speed, 0.1))
			if hoof_sound and hoof_sound.stream:
				hoof_sound.pitch_scale = randf_range(0.88, 1.12)
				hoof_sound.play()
	else:
		_hoof_timer = 0.0

	# ── Idle Audio ────────────────────────────────────────────────
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(5.0, 15.0)
		if idle_sound and idle_sound.stream:
			idle_sound.pitch_scale = randf_range(0.9, 1.1)
			idle_sound.play()
	
	# Procedural Animation
	time_alive += delta
	var speed_ratio = Vector2(velocity.x, velocity.z).length() / SPEED
	var head_pivot = mesh_base.get_node_or_null("HeadPivot")
	
	var anim_player = get_node_or_null("MeshBase/AnimationPlayer")
	
	if speed_ratio > 0.1:
		if anim_player:
			if not anim_player.is_playing() or anim_player.current_animation != "walk":
				anim_player.play("walk")
		else:
			mesh_base.position.y = sin(time_alive * 12.0) * 0.08
			if head_pivot:
				head_pivot.rotation.x = sin(time_alive * 12.0 + PI) * 0.15
				
			for i in range(4):
				var offset = 0.0
				if i == 0: offset = 0.0
				elif i == 1: offset = PI
				elif i == 2: offset = PI / 2.0
				elif i == 3: offset = PI * 1.5
				
				if i < legs.size() and legs[i]:
					var leg_angle = sin(time_alive * 12.0 + offset) * 0.6
					legs[i].rotation.x = leg_angle
					var knee = legs[i].get_node_or_null("Knee")
					if knee:
						if leg_angle < 0: knee.rotation.x = leg_angle * 1.5
						else: knee.rotation.x = 0.0
	else:
		if anim_player:
			if anim_player.current_animation != "RESET":
				anim_player.play("RESET")
		else:
			mesh_base.position.y = lerp(mesh_base.position.y, 0.0, 5.0 * delta)
			if head_pivot:
				head_pivot.rotation.x = lerp(head_pivot.rotation.x, 0.0, 5.0 * delta)
			for i in range(legs.size()):
				if legs[i]:
					legs[i].rotation.x = lerp(legs[i].rotation.x, 0.0, 5.0 * delta)
					var knee = legs[i].get_node_or_null("Knee")
					if knee:
						knee.rotation.x = lerp(knee.rotation.x, 0.0, 5.0 * delta)

func die():
	if dead: return
	dead = true

	# ── Play Death Sound ─────────────────────────────────────────
	# Orphan the AudioStreamPlayer3D to the scene root so it
	# survives queue_free() on this node. It self-destructs after play.
	if death_sound and death_sound.stream:
		var orphan = AudioStreamPlayer3D.new()
		orphan.stream = death_sound.stream
		orphan.bus = &"RetroFilter"
		orphan.volume_db = death_sound.volume_db
		orphan.max_distance = death_sound.max_distance
		orphan.unit_size = death_sound.unit_size
		orphan.pitch_scale = randf_range(0.9, 1.1)
		var scene = get_tree().current_scene
		if scene:
			scene.add_child(orphan)
			orphan.global_position = global_position + Vector3(0, 0.5, 0)
			orphan.play()
			# Self-destruct after stream length + small buffer
			var ttl = orphan.stream.get_length() + 0.5
			orphan.get_tree().create_timer(ttl).timeout.connect(orphan.queue_free)
	
	var carcass = RigidBody3D.new()
	carcass.add_to_group("carcass")
	carcass.set_meta("score_value", score_value)
	var s_name = scene_file_path.get_file().get_basename()
	if s_name == "":
		s_name = "Deer2" if "Deer" in name else "Sheep2"
	carcass.set_meta("animal_name", s_name)
	
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.5)
	shape.shape = box
	carcass.add_child(shape)
	
	carcass.set_script(load("res://scripts/carcass.gd"))
	carcass.set("animal_name", s_name)
	carcass.set("score_value", score_value)
	
	var mesh = $MeshBase
	remove_child(mesh)
	carcass.add_child(mesh)
	# Fit the collision box to the body that just landed in it, or the animal
	# rests inside an oversized box and floats above the ground.
	var fitted = CarcassPose.lay_down(mesh)
	if fitted != Vector3.ZERO:
		box.size = fitted
	
	# Make sure the carcass physics responds
	carcass.collision_layer = 1
	carcass.collision_mask = 1
	
	get_tree().current_scene.add_child(carcass)
	carcass.global_position = self.global_position + Vector3(0, 0.5, 0)
	
	queue_free()
