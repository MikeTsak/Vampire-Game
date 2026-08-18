extends AnimationPlayer
## Picks a looping clip from the creature's AI state.
##
## This lives on the AnimationPlayer rather than inside skinwalker_new.gd so the
## AI script stays untouched -- it only ever reads public state off its parent.
## Neither looping clip keys the Head bone, so the AI's head look-at keeps
## working on top of whichever one is playing.

## Clip played while the creature is holding still and watching.
@export var idle_clip: StringName = &"idle"
## Clip played while it is actually moving. "walk" for a slow stalk.
@export var moving_clip: StringName = &"run"
## Cross-fade between the two, in seconds.
@export var blend_time: float = 0.3

func _process(_delta: float) -> void:
	var body := get_parent()
	if body == null:
		return
	# get() returns null on a parent that has no such property, so this is safe
	# in the preview stage as well as in a level.
	var want: StringName = moving_clip if body.get("fleeing") == true else idle_clip
	if current_animation != String(want) and has_animation(want):
		play(want, blend_time)
