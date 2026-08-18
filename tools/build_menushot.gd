extends MainLoop
func _initialize() -> void:
	var root := Control.new()
	root.name = "MenuShot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_script(load("res://tools/menu_shot.gd"))
	var ps := PackedScene.new()
	ps.pack(root)
	print("save err=%d" % ResourceSaver.save(ps, "res://scenes/dev/MenuShot.tscn"))
	root.free()
func _process(_d: float) -> bool:
	return true
