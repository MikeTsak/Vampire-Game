extends MainLoop
func _initialize() -> void:
	var root := Node3D.new()
	root.name = "SkinwalkerTest"
	root.set_script(load("res://tools/skinwalker_test.gd"))
	var ps := PackedScene.new()
	ps.pack(root)
	print("save err=%d" % ResourceSaver.save(ps, "res://scenes/dev/SkinwalkerTest.tscn"))
	root.free()
func _process(_d: float) -> bool:
	return true
