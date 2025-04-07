extends Node2D

func _ready() -> void:
	if get_node("DEBUG"):
		$Player.position = $DEBUG.position
