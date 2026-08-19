extends "res://scripts/animal.gd"
## Drives the generated `_new` animals.
##
## Wandering, audio and the carcass handoff all come from animal.gd. What
## changes here is the animation: these models are skinned to a real armature
## and ship exactly three baked clips -- idle, walk and death -- instead of the
## per-frame node rotations the CSG-built deer2/sheep2 use. So the leg-swinging
## half of the parent's _physics_process is replaced by a clip selector, and
## death gets to play out before the body becomes a carcass.

## Metres of ground one full walk cycle covers. Playback is scaled by the ratio
## of this to actual speed, which is what keeps the hooves from skating.
@export var walk_cycle_distance: float = 1.0

@onready var _anim: AnimationPlayer = get_node_or_null("MeshBase/AnimationPlayer")

func _ready() -> void:
	super()
	if _anim and _anim.has_animation("idle"):
		_anim.play("idle")
		# Desync the herd: identical loops starting together read as clones.
		_anim.seek(randf() * _anim.get_animation("idle").length, true)

func _physics_process(delta: float) -> void:
	if dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	wander_timer -= delta
	if wander_timer <= 0.0:
		randomize_wander()

	if move_direction != Vector3.ZERO:
		var target_rotation := atan2(-move_direction.x, -move_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, 5.0 * delta)

	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED
	move_and_slide()

	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	_hooves(delta, horiz_speed)
	_voice(delta)
	_drive_animation(horiz_speed)

## Footstep and idle-call timing, lifted from the parent so that overriding
## _physics_process does not silence the animals.
func _hooves(delta: float, horiz_speed: float) -> void:
	if is_on_floor() and horiz_speed > 0.5:
		_hoof_timer -= delta
		if _hoof_timer <= 0.0:
			_hoof_timer = HOOF_INTERVAL * (SPEED / maxf(horiz_speed, 0.1))
			if hoof_sound and hoof_sound.stream:
				hoof_sound.pitch_scale = randf_range(0.88, 1.12)
				hoof_sound.play()
	else:
		_hoof_timer = 0.0

func _voice(delta: float) -> void:
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(5.0, 15.0)
		if idle_sound and idle_sound.stream:
			idle_sound.pitch_scale = randf_range(0.9, 1.1)
			idle_sound.play()

func _drive_animation(horiz_speed: float) -> void:
	if _anim == null:
		return
	var want := "walk" if horiz_speed > 0.5 else "idle"
	if _anim.current_animation != want and _anim.has_animation(want):
		_anim.play(want, 0.18)
	if want == "walk" and _anim.has_animation("walk") and walk_cycle_distance > 0.0:
		var cycles_per_second := horiz_speed / walk_cycle_distance
		_anim.speed_scale = clampf(
			cycles_per_second * _anim.get_animation("walk").length, 0.35, 2.0)
	else:
		_anim.speed_scale = 1.0

## Let the collapse play, then hand the body to the shared carcass code.
func die() -> void:
	if dead:
		return
	dead = true                      # stops the wander before the legs buckle
	velocity = Vector3.ZERO
	move_direction = Vector3.ZERO

	if _anim and _anim.has_animation("death"):
		_anim.speed_scale = 1.0
		_anim.play("death")
		await _anim.animation_finished
		if not is_inside_tree():
			return
		# animal.gd lays the carcass down itself, so give it the mesh upright
		# rather than already collapsed.
		_anim.play("idle")
		_anim.seek(0.0, true)
		_anim.stop()

	dead = false                     # ...or the parent's die() returns early
	super()
