extends Control

var elapsed = 0

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 2:
		get_tree().change_scene_to_file("res://scenes/world.tscn")
