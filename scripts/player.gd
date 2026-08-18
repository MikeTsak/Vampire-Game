extends CharacterBody3D
# Force recompile
const NORMAL_FOV = 75.0
const ADS_FOV = 50.0
const AIM_SPEED = 12.0

## The rifle sits at the origin of WeaponPivot, so these place the whole gun.
## ADS puts x at 0 and y at minus the sight height, which drops the front post
## and rear notch exactly onto the centre of the screen.
const SIGHT_HEIGHT := 0.070
var default_weapon_pos := Vector3(0.24, -0.26, -0.62)
var ads_weapon_pos := Vector3(0.0, -SIGHT_HEIGHT, -0.37)

# ── Recoil ──────────────────────────────────────────────────────
## Stiff spring with light damping: the gun snaps back hard and settles with a
## small overshoot, which is what makes a shot feel like it has mass.
const KICK_STIFF := 190.0
const KICK_DAMP := 19.0
const CAM_KICK_STIFF := 120.0
const CAM_KICK_DAMP := 13.0
const FOV_KICK_STIFF := 200.0
const FOV_KICK_DAMP := 22.0
## Seconds between shots. Slow on purpose -- it is a bolt-action.
const FIRE_COOLDOWN := 0.9

## How far the rifle tips away while the bolt is worked. Applied here rather
## than in the clip so it can be scaled out as the player enters the sights --
## at ADS the gun is close enough to the lens that any sway clips through it.
const RELOAD_SWAY_POS := Vector3(-0.03, -0.035, -0.05)
const RELOAD_SWAY_ROT := Vector3(-0.22, 0.12, 0.20)
## Shouldered, the bolt itself is behind the camera and invisible, so without a
## little motion a reload reads as nothing happening at all. These are kept an
## order of magnitude smaller than the hip values -- enough to feel the bolt
## being worked, far too small to bring anything near the near plane.
const RELOAD_SWAY_POS_ADS := Vector3(0.0, -0.012, 0.0)
const RELOAD_SWAY_ROT_ADS := Vector3(-0.05, 0.02, 0.03)

var _kick_pos := Vector3.ZERO
var _kick_pos_vel := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _kick_rot_vel := Vector3.ZERO
var _cam_kick := Vector3.ZERO
var _cam_kick_vel := Vector3.ZERO
var _fov_kick := 0.0
var _fov_kick_vel := 0.0
var _weapon_base := Vector3.ZERO
var _fov_base := NORMAL_FOV
var _horiz_speed := 0.0
## 0 = hip carry, 1 = fully shouldered. Drives weapon position, FOV and how
## much of the reload sway is allowed.
var _ads_blend := 0.0
var _reload_t := 0.0
var _reload_len := 0.0
var _cam_rest_rot := Vector3.ZERO

const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.5
const JUMP_VELOCITY = 4.5

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var is_carrying_carcass: bool = false
var has_rifle: bool = true
var carried_animal_name: String = ""
var carried_instance: Node3D = null
var is_on_tarp: bool = false
var carried_score_value: int = 5000
var frozen: bool = false

func set_frozen(f: bool):
	frozen = f
	velocity = Vector3.ZERO

@onready var head = $Head
@onready var cam = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D
@onready var interact_ray = $Head/Camera3D/InteractRay
@onready var weapon_root = $Head/Camera3D/WeaponPivot
@onready var score_label = $HUD/ScoreLabel
@onready var timer_label = $HUD/TimerLabel
@onready var interaction_label = $HUD/InteractionLabel
@onready var gun_sound: AudioStreamPlayer = get_node_or_null("GunSound")
@onready var footstep_sound: AudioStreamPlayer = get_node_or_null("FootstepSound")
@onready var muzzle_flash: Node3D = get_node_or_null(
	"Head/Camera3D/WeaponPivot/WWIRifle/Muzzle/MuzzleFlash")

# Footstep timing
var _footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.42  # seconds between footstep sounds

func _ready():
	set_physics_process(true)
	set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	head = $Head
	cam = $Head/Camera3D
	weapon_root = $Head/Camera3D/WeaponPivot
	_weapon_base = default_weapon_pos
	weapon_root.position = _weapon_base
	_fov_base = NORMAL_FOV
	_cam_rest_rot = cam.rotation
	# The view model comes close to the lens when aiming; a tighter near plane
	# keeps the receiver from being sliced open.
	cam.near = 0.02
	raycast = $Head/Camera3D/RayCast3D
	raycast.add_exception(self)
	
	if cam:
		cam.make_current()
		
	var flashlight = get_node_or_null("Head/Camera3D/Flashlight")
	if flashlight:
		flashlight.visible = true
		flashlight.light_energy = 4.0
		
	# Clear stuck transition screens
	var fader = get_tree().root.find_child("FadeRect", true, false)
	if fader:
		fader.visible = false
		fader.modulate.a = 0.0

	
	if has_node("HUD/InteractionLabel"):
		interaction_label = $HUD/InteractionLabel
	if has_node("HUD/ScoreLabel"):
		score_label = $HUD/ScoreLabel
		
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		score_label.text = "%d ₯" % gm.drachmas

func _input(event):
	if frozen:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.005)
		head.rotate_x(-event.relative.y * 0.005)
		head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		shoot()

	pass

var can_shoot: bool = true

@onready var crosshair = get_node_or_null("HUD/Crosshair")
@onready var shoulder_carcass = get_node_or_null("Head/Camera3D/CarcassMesh")

func _physics_process(delta):
	if frozen:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_W): input_dir.y = -1
	if Input.is_key_pressed(KEY_S): input_dir.y = 1
	if Input.is_key_pressed(KEY_A): input_dir.x = -1
	if Input.is_key_pressed(KEY_D): input_dir.x = 1
	input_dir = input_dir.normalized()
	
	var current_speed = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()
	
	# ── Footstep Audio ──────────────────────────────────────────────
	var horiz_speed = Vector2(velocity.x, velocity.z).length()
	_horiz_speed = horiz_speed
	if is_on_floor() and horiz_speed > 1.0:
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = FOOTSTEP_INTERVAL / (horiz_speed / WALK_SPEED)
			if footstep_sound and footstep_sound.stream:
				footstep_sound.pitch_scale = randf_range(0.9, 1.1)
				footstep_sound.play()
	else:
		_footstep_timer = 0.0  # Reset so next step fires immediately
	

## Damped spring step toward zero. Returns [value, velocity].
func _spring3(cur: Vector3, vel: Vector3, stiff: float, damp: float, delta: float) -> Array:
	vel += (-cur * stiff - vel * damp) * delta
	cur += vel * delta
	return [cur, vel]

func _process(delta: float) -> void:
	if frozen:
		return
	var aiming: bool = Input.is_action_pressed("aim")

	var r := _spring3(_kick_pos, _kick_pos_vel, KICK_STIFF, KICK_DAMP, delta)
	_kick_pos = r[0]
	_kick_pos_vel = r[1]
	r = _spring3(_kick_rot, _kick_rot_vel, KICK_STIFF, KICK_DAMP, delta)
	_kick_rot = r[0]
	_kick_rot_vel = r[1]
	r = _spring3(_cam_kick, _cam_kick_vel, CAM_KICK_STIFF, CAM_KICK_DAMP, delta)
	_cam_kick = r[0]
	_cam_kick_vel = r[1]
	_fov_kick_vel += (-_fov_kick * FOV_KICK_STIFF - _fov_kick_vel * FOV_KICK_DAMP) * delta
	_fov_kick += _fov_kick_vel * delta

	var k: float = clampf(AIM_SPEED * delta, 0.0, 1.0)
	_ads_blend = lerpf(_ads_blend, 1.0 if aiming else 0.0, k)
	_weapon_base = default_weapon_pos.lerp(ads_weapon_pos, _ads_blend)
	_fov_base = lerpf(NORMAL_FOV, ADS_FOV, _ads_blend)

	# Reload sway, faded out by the aim blend. Scaling by (1 - blend) also covers
	# aiming part-way through a reload, or releasing aim mid-cycle: the sway
	# follows the sights in and out instead of snapping.
	var sway_pos := Vector3.ZERO
	var sway_rot := Vector3.ZERO
	if _reload_t > 0.0:
		_reload_t = maxf(0.0, _reload_t - delta)
		var done: float = 1.0 - _reload_t / maxf(_reload_len, 0.001)
		var env: float = sin(clampf(done, 0.0, 1.0) * PI)
		sway_pos = RELOAD_SWAY_POS.lerp(RELOAD_SWAY_POS_ADS, _ads_blend) * env
		sway_rot = RELOAD_SWAY_ROT.lerp(RELOAD_SWAY_ROT_ADS, _ads_blend) * env

	if weapon_root:
		weapon_root.position = _weapon_base + _kick_pos + sway_pos
		weapon_root.rotation = _kick_rot + sway_rot
	if cam:
		cam.fov = _fov_base + _fov_kick
		# Recoil rides the Camera3D, not the Head. Mouse look owns
		# head.rotation.x, and two writers on one axis fight each other.
		cam.rotation = _cam_rest_rot + _cam_kick
	if crosshair:
		crosshair.visible = aiming

	_update_weapon_anim(aiming)

func _update_weapon_anim(aiming: bool) -> void:
	if weapon_root == null:
		return
	var anim: AnimationPlayer = weapon_root.get_node_or_null("AnimationPlayer")
	if anim == null:
		return
	# Never cut the bolt cycle or a reload short.
	if anim.is_playing() and anim.current_animation in ["shoot", "reload"]:
		return
	var want := "idle"
	if not aiming and _horiz_speed > 1.0:
		want = "walk_bob"
	if anim.current_animation != want and anim.has_animation(want):
		anim.play(want, 0.25)

func shoot():
	if not can_shoot: return
	can_shoot = false
	# ── Gunshot Audio ───────────────────────────────────────────────
	if gun_sound and gun_sound.stream:
		gun_sound.pitch_scale = 1.0                     # Real guns don't vary in pitch
		gun_sound.volume_db = randf_range(-0.5, 0.5)    # Tiny vol variation per shot
		gun_sound.play()
	elif has_node("ShootAudio"):
		$ShootAudio.play()
		
	if muzzle_flash and muzzle_flash.has_method("fire"):
		muzzle_flash.fire()

	# Recoil impulses. Shouldering the rifle braces it, so aimed shots kick less.
	var brace: float = 0.6 if Input.is_action_pressed("aim") else 1.0
	_kick_pos_vel += Vector3(randf_range(-0.08, 0.08), 0.42, 1.45) * brace
	_kick_rot_vel += Vector3(2.4, randf_range(-0.35, 0.35), randf_range(-0.9, 0.9)) * brace
	_cam_kick_vel += Vector3(0.95, randf_range(-0.5, 0.5), randf_range(-0.6, 0.6)) * brace
	_fov_kick_vel += 55.0 * brace

	# Work the bolt. The lock below runs for exactly this clip's length, so the
	# player can never fire again part-way through the reload.
	var reload_time := FIRE_COOLDOWN
	if weapon_root and weapon_root.has_node("AnimationPlayer"):
		var anim: AnimationPlayer = weapon_root.get_node("AnimationPlayer")
		if anim.has_animation("reload"):
			anim.stop()
			anim.play("reload")
			reload_time = anim.get_animation("reload").length
	_reload_len = reload_time
	_reload_t = reload_time
		
	if raycast and raycast.is_colliding():
		for i in range(raycast.get_collision_count()):
			var target = raycast.get_collider(i)
			if target and target.has_method("die") and not target.get("dead"):
				target.die()
				break
	
	await get_tree().create_timer(reload_time).timeout
	can_shoot = true

func pickup_animal(animal_name: String = "Deer", score: int = 5000):
	is_carrying_carcass = true
	carried_animal_name = animal_name
	carried_score_value = score
	if shoulder_carcass:
		shoulder_carcass.visible = false
	
	if carried_instance:
		carried_instance.queue_free()
		
	var scene = load("res://scenes/animals/" + animal_name + ".tscn")
	if scene:
		carried_instance = scene.instantiate()
		carried_instance.set_script(null)
		carried_instance.process_mode = Node.PROCESS_MODE_DISABLED
		head.get_node("Camera3D").add_child(carried_instance)
		carried_instance.transform = Transform3D()
		carried_instance.position = Vector3(-0.6, -0.5, -0.3)
		carried_instance.rotation_degrees = Vector3(180, 90, 90)
		carried_instance.scale = Vector3(0.5, 0.5, 0.5)

	if interaction_label: interaction_label.text = "Carrying carcass. Drop it in the tarp."
	
func drop_animal() -> String:
	if is_carrying_carcass:
		is_carrying_carcass = false
		if shoulder_carcass:
			shoulder_carcass.visible = false
		if carried_instance:
			carried_instance.queue_free()
			carried_instance = null
			
		var gm = get_node_or_null("/root/GameManager")
		if gm:
			gm.add_score(carried_score_value)
			if score_label: score_label.text = "%d ₯" % gm.drachmas
		if interaction_label: interaction_label.text = ""
		
		var dropped_name = carried_animal_name
		carried_animal_name = ""
		
		return dropped_name
	return ""
