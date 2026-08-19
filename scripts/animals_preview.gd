extends Node3D
## Dev stage for the generated `_new` animals: the whole family in a row, all
## playing the same clip so silhouettes, scale and texture seams can be
## compared side by side. Nothing in the shipped levels uses this.
##
## The wander AI is switched off here, otherwise they walk out of frame; keys
## 1/2/3 swap the clip.

const CLIPS := ["idle", "walk", "death"]

## Clip every animal on the stage plays. Change it in the inspector, or with
## the number keys while running.
@export_enum("idle", "walk", "death") var clip: String = "walk"

func _ready() -> void:
	_play(clip)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var i := (event as InputEventKey).keycode - KEY_1
		if i >= 0 and i < CLIPS.size():
			clip = CLIPS[i]
			_play(clip)

func _play(name: String) -> void:
	for c in get_children():
		var ap := c.get_node_or_null("MeshBase/AnimationPlayer") as AnimationPlayer
		if ap == null:
			continue
		c.set_physics_process(false)     # stand still for the camera
		if ap.has_animation(name):
			ap.stop()
			ap.play(name)
	print("[animals preview] playing '%s'" % name)
