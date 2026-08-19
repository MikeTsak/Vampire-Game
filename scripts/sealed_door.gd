extends Area3D
## The way out, at the far end of the ground-floor corridor.
##
## It is deliberately the most visible thing on the floor -- daylight leaks
## around it the whole length of the walk -- and it does not open. Reaching it
## and being told so is the point; a plain wall there would just read as level
## geometry running out.

@export_multiline var message: String = "Chained from the outside.\nThe way in was not a way out."

var _claimed: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _label_for(body: Node3D) -> Label:
	return body.get_node_or_null("HUD/InteractionLabel")


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	# The carry prompt lives on the same label and matters more; leave it alone.
	if body.get("is_carrying_carcass"):
		return
	var label := _label_for(body)
	if label:
		label.text = message
		_claimed = true


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player") or not _claimed:
		return
	_claimed = false
	var label := _label_for(body)
	if label and label.text == message:
		label.text = ""
