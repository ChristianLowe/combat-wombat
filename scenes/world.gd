extends Node2D

@onready var goal_area: Area2D = $GoalArea
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	if get_node("DEBUG"):
		$Player.position = $DEBUG.position
	if not goal_area:
		printerr("GoalArea node not found! Cannot connect timer stop signal.")
		return
	if not hud:
		printerr("HUD node not found! Cannot connect timer stop signal.")
		return
	goal_area.body_entered.connect(_on_goal_area_body_entered)

func _on_goal_area_body_entered(body: Node2D) -> void:
	if body.get_collision_layer_value(1):
		print("Player detected in GoalArea!") # Optional debug message
		hud.stop_timer()
