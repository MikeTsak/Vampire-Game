extends Control

var models = [
	"res://scenes/animals/Deer.tscn",
	"res://scenes/animals/Sheep.tscn",
	"res://scenes/props/Rifle.tscn",
	"res://scenes/environment/FirTree.tscn",
	"res://scenes/environment/PineTree.tscn",
	"res://scenes/environment/PlatanusTree.tscn"
]
var current_idx = 2
var current_model = null

@onready var model_mount = $SubViewportContainer/SubViewport/World/ModelMount

func _ready():
	$UI/PrevButton.pressed.connect(_on_prev_pressed)
	$UI/NextButton.pressed.connect(_on_next_pressed)
	$UI/BackButton.pressed.connect(_on_back_pressed)
	load_model()

func _process(delta):
	if current_model:
		current_model.rotation.y += delta * 0.5

func load_model():
	if current_model:
		current_model.queue_free()
	
	var scene = load(models[current_idx])
	if scene:
		current_model = scene.instantiate()
		model_mount.add_child(current_model)
		
		# Disable processing so animals don't walk away
		current_model.set_process(false)
		current_model.set_physics_process(false)
		
		# If it's the rifle, center it better
		if "Rifle" in models[current_idx]:
			current_model.position.y = 0.5

func _on_prev_pressed():
	current_idx -= 1
	if current_idx < 0:
		current_idx = models.size() - 1
	load_model()

func _on_next_pressed():
	current_idx = (current_idx + 1) % models.size()
	load_model()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
