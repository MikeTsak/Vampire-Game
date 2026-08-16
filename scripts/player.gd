extends CharacterBody3D
# Force recompile
const NORMAL_FOV = 75.0
const ADS_FOV = 50.0
const AIM_SPEED = 12.0

var default_weapon_pos := Vector3(0.3, -0.2, -0.6) 
var ads_weapon_pos := Vector3(0.0, -0.2, -0.5)

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

func _ready():
	set_physics_process(true)
	set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	head = $Head
	cam = $Head/Camera3D
	weapon_root = $Head/Camera3D/WeaponPivot
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
	
	var target_fov = NORMAL_FOV
	var target_pos = default_weapon_pos

	if Input.is_action_pressed("aim"):
		target_fov = ADS_FOV
		target_pos = ads_weapon_pos

		if weapon_root and weapon_root.has_node("AnimationPlayer"):
			if weapon_root.get_node("AnimationPlayer").current_animation == "idle":
				weapon_root.get_node("AnimationPlayer").stop()
		if crosshair: crosshair.visible = true
	else:
		if weapon_root and weapon_root.has_node("AnimationPlayer"):
			var anim = weapon_root.get_node("AnimationPlayer")
			if anim.has_animation("idle") and not anim.is_playing():
				anim.play("idle")
		if crosshair: crosshair.visible = false

	if cam:
		cam.fov = lerp(cam.fov, target_fov, AIM_SPEED * delta)
	if weapon_root:
		weapon_root.position = weapon_root.position.lerp(target_pos, AIM_SPEED * delta)

func shoot():
	if not can_shoot: return
	can_shoot = false
	print("Bang!")
	if has_node("ShootAudio"):
		$ShootAudio.play()
		
	if weapon_root and weapon_root.has_node("AnimationPlayer"):
		weapon_root.get_node("AnimationPlayer").stop()
		weapon_root.get_node("AnimationPlayer").play("shoot")
		
	if raycast and raycast.is_colliding():
		for i in range(raycast.get_collision_count()):
			var target = raycast.get_collider(i)
			if target and target.has_method("die") and not target.get("dead"):
				target.die()
				break
	
	await get_tree().create_timer(1.0).timeout
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
