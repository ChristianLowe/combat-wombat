extends Control

var elapsed = 0

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > .25:
		$CenterContainer/TextureRect1.visible = true
	if elapsed > .95:
		$CenterContainer/TextureRect2.visible = true
	if elapsed > 1.76:
		$CenterContainer/TextureRect3.visible = true
	if elapsed > 2.5:
		$CenterContainer/TextureRect4.visible = true
	if elapsed > 7.5:
		get_tree().change_scene_to_file("res://scenes/world.tscn")
