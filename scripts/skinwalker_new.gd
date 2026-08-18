extends Node3D

@export var min_radius: float = 18.0
@export var max_radius: float = 32.0
@export var flee_distance: float = 10.0
@export var stare_time_limit: float = 1.2
@export var view_dot_threshold: float = 0.94
@export var reroll_interval: float = 20.0
@export var flee_speed: float = 22.0
@export var jitter_strength: float = 1.6
@export var park_trigger_radius: float = 70.0
@export var park_search_timeout: float = 5.0

var player: Node3D = null
var player_cam: Node3D = null
var stare_timer: float = 0.0
var idle_timer: float = 0.0
var relocating: bool = false
var fleeing: bool = false
var active: bool = false
var park_of_souls: Node3D = null
var park_search_timer: float = 0.0
var park_search_done: bool = false
var debug_label: Label = null

@onready var mesh_base = $MeshBase
@onready var skeleton: Skeleton3D = $MeshBase/Skeleton3D
var head_bone_idx: int = -1

func _ready():
	randomize()
	idle_timer = reroll_interval
	visible = false
	head_bone_idx = skeleton.find_bone("Head")
	_create_debug_label()
	call_deferred("_find_player")

func _create_debug_label():
	var layer = CanvasLayer.new()
	layer.layer = 20
	var label = Label.new()
	label.add_theme_color_override("font_color", Color(1, 0.15, 0.15))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 22)
	label.position = Vector2(16, 16)
	label.text = ""
	layer.add_child(label)
	get_tree().root.add_child.call_deferred(layer)
	debug_label = label

func _set_active(new_active: bool):
	if active == new_active:
		return
	active = new_active
	if active:
		print("Skinwalker Activated")
	if debug_label:
		debug_label.text = "Skinwalker Activated" if active else ""

func _find_player():
	player = get_tree().get_first_node_in_group("player")
	if player:
		player_cam = player.get_node_or_null("Head/Camera3D")

func _process(delta):
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
	if not player_cam:
		player_cam = player.get_node_or_null("Head/Camera3D")

	if not active:
		_process_dormant(delta)
		return

	if fleeing:
		_process_flee(delta)
		return

	if relocating or not visible:
		return

	_process_idle(delta)

func _process_dormant(delta):
	# Stay completely inert until the player wanders toward the Park of Souls
	# (or, in a level with no Park of Souls, fall back to the old always-roaming
	# behavior after a short grace period so it doesn't just sit disabled forever).
	if not park_search_done:
		if not park_of_souls:
			park_of_souls = get_tree().current_scene.find_child("ParkOfSouls", true, false)
		park_search_timer += delta
		if park_of_souls or park_search_timer >= park_search_timeout:
			park_search_done = true
			if not park_of_souls:
				_set_active(true)
				_reposition_far()
				return

	if park_of_souls and player.global_position.distance_to(park_of_souls.global_position) < park_trigger_radius:
		_set_active(true)
		_reposition_far()

func _process_idle(delta):
	# It never approaches or retreats while idle -- it plants itself and just
	# slowly, deliberately turns to keep facing (and "watching") the player,
	# no matter where they move. Classic living-statue horror beat.
	var look_target = player.global_position
	look_target.y = global_position.y
	if look_target.distance_to(global_position) > 0.01:
		var target_yaw = global_transform.looking_at(look_target, Vector3.UP).basis.get_euler().y
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 1.8)

	# Subtle unnatural sway on top of that, even while "idle" this thing should never look relaxed.
	mesh_base.rotation.y = sin(Time.get_ticks_msec() * 0.0003) * 0.05

	_track_player_with_head(delta)

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

	if dist < flee_distance or stare_timer >= stare_time_limit:
		_start_flee()
	elif idle_timer <= 0.0:
		_relocate()

func _track_player_with_head(delta):
	# Independent neck/head swivel toward the player, on top of (and faster
	# than) the slow body turn -- the "eyes never leave you" beat. Allowed to
	# swing further than a real neck could, since that wrongness is the point.
	if head_bone_idx < 0:
		return
	var target = player.global_position
	if player_cam:
		target = player_cam.global_position
	var dir = target - global_position
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var world_look = Transform3D(Basis(), Vector3.ZERO).looking_at(dir, Vector3.UP).basis
	var body_basis = Basis(Vector3.UP, rotation.y)
	var head_pose_basis = body_basis.inverse() * world_look
	var current_pose = skeleton.get_bone_pose_rotation(head_bone_idx)
	var target_pose = head_pose_basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(head_bone_idx, current_pose.slerp(target_pose, clamp(delta * 6.0, 0.0, 1.0)))

func _reset_head_pose():
	if head_bone_idx >= 0 and skeleton:
		skeleton.reset_bone_pose(head_bone_idx)

func _start_flee():
	fleeing = true
	stare_timer = 0.0
	_reset_head_pose()

func _process_flee(delta):
	if not visible:
		return
	var away = global_position - player.global_position
	away.y = 0
	if away.length() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	away = away.normalized()
	# Fast and spastic: mostly run away, but with sharp erratic jitter layered on
	# top so the motion reads as unnatural rather than a clean flee-line.
	var jitter = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)) * jitter_strength
	var move_dir = (away * 3.0 + jitter).normalized()
	global_position += move_dir * flee_speed * delta
	global_position.y = _get_ground_height(global_position.x, global_position.z)
	look_at(global_position - move_dir, Vector3.UP)
	rotation.x = 0
	rotation.z = 0

	var dist = global_position.distance_to(player.global_position)
	var forward = -player_cam.global_transform.basis.z if player_cam else -player.global_transform.basis.z
	var dir_to_self = (global_position - player.global_position).normalized()
	var dot = forward.dot(dir_to_self)
	var out_of_view = dot < 0.5

	if dist > max_radius or out_of_view:
		fleeing = false
		_relocate()

func _relocate():
	relocating = true
	stare_timer = 0.0
	idle_timer = randf_range(reroll_interval * 0.5, reroll_interval * 1.5)
	visible = false
	_reset_head_pose()
	# Unpredictable hide time -- sometimes it's back almost immediately, sometimes
	# it takes a while, so there's no reliable rhythm to learn.
	var hide_time = randf_range(0.4, 3.0)
	await get_tree().create_timer(hide_time).timeout
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
