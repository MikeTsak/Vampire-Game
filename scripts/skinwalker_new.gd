extends Node3D

@export var min_radius: float = 60.0
@export var max_radius: float = 95.0
@export var flee_distance: float = 35.0
@export var stare_time_limit: float = 2.0
@export var view_dot_threshold: float = 0.94
@export var reroll_interval: float = 30.0

var player: Node3D = null
var player_cam: Node3D = null
var stare_timer: float = 0.0
var idle_timer: float = 0.0
var relocating: bool = false

@onready var mesh_base = $MeshBase

func _ready():
	randomize()
	idle_timer = reroll_interval
	visible = false
	call_deferred("_find_player_and_spawn")

func _find_player_and_spawn():
	player = get_tree().get_first_node_in_group("player")
	if player:
		player_cam = player.get_node_or_null("Head/Camera3D")
		_reposition_far()

func _process(delta):
	if relocating:
		return
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
	if not visible:
		return

	# Subtle unnatural sway, even while "idle" this thing should never look relaxed.
	mesh_base.rotation.y = sin(Time.get_ticks_msec() * 0.0003) * 0.05

	var to_self = global_position - player.global_position
	var dist = to_self.length()

	var being_watched = false
	if dist > 0.01:
		var forward = -player.global_transform.basis.z
		if player_cam:
			forward = -player_cam.global_transform.basis.z
		var dir_to_self = to_self.normalized()
		var dot = forward.dot(-dir_to_self)
		if dot > view_dot_threshold and dist < max_radius + 20.0:
			being_watched = true

	if being_watched:
		stare_timer += delta
	else:
		stare_timer = max(0.0, stare_timer - delta * 2.0)

	idle_timer -= delta

	if dist < flee_distance or stare_timer >= stare_time_limit or idle_timer <= 0.0:
		_relocate()

func _relocate():
	relocating = true
	stare_timer = 0.0
	idle_timer = reroll_interval
	visible = false
	await get_tree().create_timer(0.2).timeout
	_reposition_far()
	relocating = false

func _reposition_far():
	if not player or not is_instance_valid(player):
		visible = false
		return
	var angle = randf_range(0.0, TAU)
	var radius = randf_range(min_radius, max_radius)
	var offset = Vector3(sin(angle) * radius, 0, cos(angle) * radius)
	var target = player.global_position + offset
	target.y = _get_ground_height(target.x, target.z)
	global_position = target
	look_at(player.global_position, Vector3.UP)
	rotation.x = 0
	rotation.z = 0
	visible = true

func _get_ground_height(x: float, z: float) -> float:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -50, z))
	var result = space_state.intersect_ray(query)
	if result:
		return result.position.y
	return 0.0
