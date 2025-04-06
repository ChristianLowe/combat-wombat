extends CharacterBody2D

# Movement parameters
@export var speed = 300.0
@export var gravity = 800.0
@export var jump_velocity = -400.0
@export var dash_speed = 600.0
@export var dash_cooldown = 0.5
@export var initial_dash_duration = 0.15 # How long the initial dash lasts if terrain isn't hit

# Collision Layer Numbers
const PLAYER_LAYER = 1
const WALL_LAYER = 2         # Normal walls - STOP dash
const DASH_TERRAIN_LAYER = 3 # Special terrain - Dash THROUGH

# Dash States
enum DashState { NONE, INITIAL, TERRAIN }
var current_dash_state = DashState.NONE

var dash_direction = Vector2.ZERO
var dash_cooldown_timer = 0.0
var initial_dash_timer = 0.0 # Timer for the initial dash phase

var original_collision_mask: int
var original_collision_layer: int

func _ready():
	original_collision_mask = get_collision_mask()
	original_collision_layer = get_collision_layer()
	set_collision_layer_value(PLAYER_LAYER, true)
	add_to_group("player")
	# Recommendation: Add wall nodes to "walls" group
	# Recommendation: Add dash terrain nodes to "dash_terrain" group
	
	# Ensure input actions are set up in Project > Project Settings > Input Map
	# Need: "ui_left", "ui_right", "ui_up", "ui_down", "dash", "jump" (or whatever you use for jump)

func _physics_process(delta):
	# --- Dash Cooldown ---
	if dash_cooldown_timer > 0 and current_dash_state == DashState.NONE:
		dash_cooldown_timer -= delta

	# --- State Machine for Dashing ---
	match current_dash_state:
		DashState.NONE:
			# --- Normal Movement Logic ---
			process_normal_movement(delta)

			# --- Check for Dash Input ---
			if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0:
				# Check if *any* directional input is held
				var h_input = Input.get_axis("ui_left", "ui_right")
				var v_input = Input.get_axis("ui_up", "ui_down") # Godot default: Up = -1, Down = 1

				if h_input != 0 or v_input != 0: # Only allow dash if a direction is pressed
					_start_dash() # Call without arguments now
					
					# Execute first frame of dash movement immediately after starting
					if current_dash_state != DashState.NONE:
						velocity = dash_direction * dash_speed
						# Make sure move_and_slide uses dash collision settings
						# Set up in _start_dash, so this should be correct
						move_and_slide()
						# Skip normal move_and_slide call at the end for this frame
						return

		DashState.INITIAL:
			# --- Initial Timed Dash Phase ---
			initial_dash_timer -= delta

			var is_in_terrain = _check_overlap_with_dash_terrain()

			if is_in_terrain:
				print("Initial dash entered terrain, extending.")
				current_dash_state = DashState.TERRAIN
				velocity = dash_direction * dash_speed
				move_and_slide()
				if _check_for_wall_collision():
					_stop_dash(true)
				return

			elif initial_dash_timer <= 0:
				print("Initial dash timed out.")
				_stop_dash(false) # Keep momentum

			else:
				# Still in initial dash
				velocity = dash_direction * dash_speed
				move_and_slide()
				if _check_for_wall_collision():
					_stop_dash(true)
				if current_dash_state != DashState.NONE:
					return

		DashState.TERRAIN:
			# --- Terrain Following Dash Phase ---
			var is_in_terrain = _check_overlap_with_dash_terrain()

			if not is_in_terrain:
				print("Exited terrain during dash.")
				_stop_dash(false) # Keep momentum
			else:
				# Still in terrain
				velocity = dash_direction * dash_speed
				move_and_slide()
				if _check_for_wall_collision():
					_stop_dash(true)
				if current_dash_state != DashState.NONE:
					return

	# --- Final Movement Execution ---
	# (Handles applying gravity/friction AFTER dash ends, preserving momentum)
	if current_dash_state == DashState.NONE:
		# Re-apply gravity if needed
		if not is_on_floor():
			velocity.y += gravity * delta

		# Apply friction if needed
		var horizontal_input_check = Input.get_axis("ui_left", "ui_right")
		# Apply friction only if not actively moving horizontally via input
		# Note: Vertical velocity is handled by gravity
		if horizontal_input_check == 0:
			velocity.x = move_toward(velocity.x, 0, speed)

		# Final move for the frame if normal movement occurred or dash ended
		move_and_slide()

		# Sprite flipping based on horizontal velocity
		if not is_dashing(): # Only flip sprite if not currently mid-dash
			if velocity.x > 0:
				$Sprite2D.flip_h = false
			elif velocity.x < 0:
				$Sprite2D.flip_h = true


func process_normal_movement(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	# Handle Jump (Using "jump" action for clarity, map to Space or Up as needed)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Get horizontal input
	var horizontal_input = Input.get_axis("ui_left", "ui_right")

	# Apply horizontal movement (velocity might be high from dash exit)
	if horizontal_input:
		velocity.x = horizontal_input * speed
	# Friction is handled after the match statement


# Helper to check for terrain overlap
func _check_overlap_with_dash_terrain() -> bool:
	var terrain_check_mask = (1 << (DASH_TERRAIN_LAYER - 1))
	var current_move_mask = get_collision_mask()
	set_collision_mask(terrain_check_mask)
	var is_overlapping = test_move(global_transform, Vector2.ZERO)
	set_collision_mask(current_move_mask)
	return is_overlapping

# Helper to check for wall collision after move_and_slide
func _check_for_wall_collision() -> bool:
	var collision = get_last_slide_collision()
	if collision:
		var collider = collision.get_collider()
		if collider and collider.is_in_group("walls"):
			return true
	return false


# Updated function to determine dash direction based on input
func _start_dash(): # Removed h_input parameter
	if current_dash_state != DashState.NONE: return

	# Get current inputs inside the function
	var h_input = Input.get_axis("ui_left", "ui_right")
	var v_input = Input.get_axis("ui_up", "ui_down") # Default: Up = -1, Down = 1

	var potential_direction = Vector2.ZERO

	# --- Determine Dash Direction (Prioritize Vertical) ---
	if v_input != 0:
		# Vertical input detected, dash up or down
		potential_direction = Vector2(0, v_input)
	elif h_input != 0:
		# No vertical input, but horizontal input detected, dash left or right
		potential_direction = Vector2(h_input, 0)
	else:
		# No directional input was held when dash was pressed (should be rare due to check before call)
		printerr("Dash initiated without directional input!")
		return # Don't start the dash

	print("Starting dash (Initial Phase). Direction: ", potential_direction)
	current_dash_state = DashState.INITIAL
	initial_dash_timer = initial_dash_duration
	dash_direction = potential_direction.normalized() # Normalize for consistent speed

	# --- Configure Collision & Cooldown (Same as before) ---
	if original_collision_mask == 0: original_collision_mask = get_collision_mask()
	if original_collision_layer == 0: original_collision_layer = get_collision_layer()

	var dash_movement_mask = original_collision_mask
	dash_movement_mask |= (1 << (WALL_LAYER - 1))
	dash_movement_mask &= ~(1 << (DASH_TERRAIN_LAYER - 1))
	set_collision_mask(dash_movement_mask)

	set_collision_layer_value(PLAYER_LAYER, false) # Disable self-collision layer

	dash_cooldown_timer = dash_cooldown


func _stop_dash(hit_wall: bool):
	if current_dash_state == DashState.NONE: return

	var previous_state = current_dash_state
	print("Stopping dash. Reason: %s" % ("Wall Collision" if hit_wall else "Timeout/Exit Terrain"))
	current_dash_state = DashState.NONE

	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer)
	set_collision_layer_value(PLAYER_LAYER, true)

	if hit_wall:
		velocity = Vector2.ZERO
	# else: Keep momentum (velocity is not changed)

# Public helper function to check if dashing (useful for other scripts/animations)
func is_dashing() -> bool:
	return current_dash_state != DashState.NONE

# Input Map actions needed: "ui_left", "ui_right", "ui_up", "ui_down", "dash", "jump"
