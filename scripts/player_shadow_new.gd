extends Node3D
## Drives the player's shadow body.
##
## The player is first person, so this rig is never drawn -- its MeshInstance3D
## is shadows-only. All it has to do is hold a pose that matches what the player
## is actually doing, so the silhouette thrown across the ground reads as a man
## walking, running or shouldering the rifle.
##
## Everything it needs is already public on player.gd, so nothing there had to
## change: velocity for the gait, _ads_blend for the aim.

## Below this the player counts as standing still.
const WALK_MIN := 0.6
## Sprinting is 8.5 and walking 5.0, so this sits between them.
const RUN_MIN := 6.2
## Metres of ground one full cycle of each clip covers, used to keep the feet
## from skating. Two steps per cycle.
const WALK_CYCLE_DISTANCE := 1.55
const RUN_CYCLE_DISTANCE := 2.60

@onready var _anim: AnimationPlayer = get_node_or_null("AnimationPlayer")

var _player: Node = null

func _ready() -> void:
	_player = get_parent()
	if _anim:
		_anim.play("idle")

func _process(_delta: float) -> void:
	if _anim == null or _player == null:
		return

	var vel: Vector3 = _player.velocity if "velocity" in _player else Vector3.ZERO
	var speed := Vector2(vel.x, vel.z).length()
	var ads: float = _player.get("_ads_blend") if _player.get("_ads_blend") != null else 0.0

	var want := "idle"
	var cycle := 0.0
	if ads > 0.5:
		want = "aim"
	elif speed > RUN_MIN:
		want = "run"
		cycle = RUN_CYCLE_DISTANCE
	elif speed > WALK_MIN:
		want = "walk"
		cycle = WALK_CYCLE_DISTANCE

	if _anim.current_animation != want and _anim.has_animation(want):
		_anim.play(want, 0.18)

	# match the stride to the ground actually covered
	if cycle > 0.0 and _anim.has_animation(want):
		_anim.speed_scale = clampf(
			speed / cycle * _anim.get_animation(want).length, 0.4, 2.2)
	else:
		_anim.speed_scale = 1.0
