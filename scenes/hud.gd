# HUD.gd
extends CanvasLayer

# Get references to the nodes we need to update.
# Using %UniqueName syntax is often safer if you rename nodes above it.
# Ensure TimerLabel has "Make Unique Name In Owner" checked in the Scene panel (right-click node).
# Or use the full path: @onready var timer_label = $TimerContainer/TimerLabel
@onready var timer_label: Label = $TimerContainer/TimerLabel

var elapsed_time: float = 0.0
var timer_running: bool = false

func _ready() -> void:
	# Reset and start the timer when the HUD is ready (usually when the level loads)
	start_timer()
	# Ensure initial display is correct even if the first _process frame is delayed
	update_timer_display()

func _process(delta: float) -> void:
	if timer_running:
		elapsed_time += delta
		update_timer_display()

func update_timer_display() -> void:
	# Format the time into Minutes:Seconds.Milliseconds
	var total_seconds: int = int(elapsed_time)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	var milliseconds: int = int((elapsed_time - total_seconds) * 100) # Two decimal places for ms

	# Use string formatting to ensure leading zeros (e.g., 01:05.09)
	timer_label.text = "%02d:%02d.%02d" % [minutes, seconds, milliseconds]
	# Alternative format without milliseconds:
	# timer_label.text = "%02d:%02d" % [minutes, seconds]

func start_timer() -> void:
	elapsed_time = 0.0
	timer_running = true
	print("Timer started!") # Optional debug message

func stop_timer() -> void:
	timer_running = false
	timer_label.add_theme_color_override("font_color", Color.PALE_GREEN)
	print("Timer stopped! Final time: %s" % timer_label.text) # Optional debug message
	# You might want to do something with the final time here, like save it.

func get_elapsed_time() -> float:
	# Useful if other scripts need the raw time value
	return elapsed_time

# --- How to stop the timer ---
# You need to call stop_timer() when the player completes the level.
# Example: Connect a signal from your player or level goal object.
#
# Assuming your player node has a signal called 'level_completed':
# In the _ready function of the script where the player is instance (e.g., YourLevelScene):
#   $Player.level_completed.connect($HUD.stop_timer)
#
# Or, if the goal object detects completion and has a signal 'player_reached_goal':
# In the _ready function of YourLevelScene:
#	$GoalArea.body_entered.connect($HUD.stop_timer)
