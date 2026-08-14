extends CharacterBody3D

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

func _ready():
	add_to_group("animals")
	if "Baby" in name or "Baby" in scene_file_path:
		score_value = 10000
	randomize_wander()

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
	mesh.position = Vector3.ZERO
	mesh.rotation.z = PI / 2
	mesh.rotation.x = PI
	
	# Make sure the carcass physics responds
	carcass.collision_layer = 1
	carcass.collision_mask = 1
	
	get_tree().current_scene.add_child(carcass)
	carcass.global_position = self.global_position + Vector3(0, 0.5, 0)
	
	queue_free()
