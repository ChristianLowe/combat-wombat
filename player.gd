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

func _physics_process(delta):
	# --- Dash Cooldown ---
	if dash_cooldown_timer > 0 and current_dash_state == DashState.NONE:
		# Cooldown only ticks down when not actively dashing
		dash_cooldown_timer -= delta

	# --- State Machine for Dashing ---
	match current_dash_state:
		DashState.NONE:
			# --- Normal Movement Logic ---
			process_normal_movement(delta)
			# Check for dash input
			var horizontal_input = Input.get_axis("ui_left", "ui_right")
			if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0 and horizontal_input != 0:
				_start_dash(horizontal_input)
				# Execute first frame of dash movement immediately after starting
				if current_dash_state != DashState.NONE:
					velocity = dash_direction * dash_speed
					move_and_slide()
					# Skip normal move_and_slide call at the end for this frame
					return

		DashState.INITIAL:
			# --- Initial Timed Dash Phase ---
			initial_dash_timer -= delta

			# Check for overlap with Dash Terrain BEFORE moving
			var is_in_terrain = _check_overlap_with_dash_terrain()

			if is_in_terrain:
				# Entered terrain, transition to terrain dash state
				print("Initial dash entered terrain, extending.")
				current_dash_state = DashState.TERRAIN
				# Fall through to TERRAIN state logic within the same frame if desired,
				# or handle next frame. Handling next frame is safer.
				# For now, let's process TERRAIN state next frame. Set velocity and move for *this* frame.
				velocity = dash_direction * dash_speed
				move_and_slide() # Use dash mask (hit walls, ignore terrain)
				if _check_for_wall_collision(): # Check wall hit immediately
					_stop_dash(true) # Stop if wall hit
				return # Skip normal processing

			elif initial_dash_timer <= 0:
				# Initial dash time ran out, and we are NOT in terrain
				print("Initial dash timed out.")
				_stop_dash(false) # Stop dash, keep momentum briefly
				# Fall through to normal movement processing

			else:
				# Still in initial dash, timer hasn't run out, not in terrain
				velocity = dash_direction * dash_speed
				move_and_slide() # Use dash mask (hit walls, ignore terrain)
				if _check_for_wall_collision():
					_stop_dash(true) # Stop if wall hit
				# If still dashing, skip normal processing
				if current_dash_state != DashState.NONE:
					return

		DashState.TERRAIN:
			# --- Terrain Following Dash Phase ---
			# Check for overlap with Dash Terrain
			var is_in_terrain = _check_overlap_with_dash_terrain()

			if not is_in_terrain:
				# Exited terrain
				print("Exited terrain during dash.")
				_stop_dash(false) # Stop dash, keep momentum
				# Fall through to normal movement processing
			else:
				# Still in terrain, continue dash movement
				velocity = dash_direction * dash_speed
				move_and_slide() # Use dash mask (hit walls, ignore terrain)
				if _check_for_wall_collision():
					_stop_dash(true) # Stop if wall hit
				# If still dashing, skip normal processing
				if current_dash_state != DashState.NONE:
					return

	# --- Final Movement Execution (only if not dashing or dash just ended) ---
	# This handles applying gravity/friction AFTER dash ends, preserving momentum
	if current_dash_state == DashState.NONE:
		# Only call move_and_slide here if it wasn't called during dash logic end
		# The structure above ensures move_and_slide happens within the states,
		# and normal movement is processed by process_normal_movement if needed.
		# We might need to re-apply gravity/friction here if dash just ended.

		# Re-apply gravity if needed (especially after exiting terrain dash)
		if not is_on_floor():
			velocity.y += gravity * delta

		# Apply friction if needed (velocity might still be dash_speed)
		var horizontal_input = Input.get_axis("ui_left", "ui_right")
		if horizontal_input == 0: # Only apply friction if no input overrides
			velocity.x = move_toward(velocity.x, 0, speed) # Use normal speed for friction rate

		# Final move for the frame if normal movement occurred
		move_and_slide()

		# Sprite flipping based on final velocity
		if velocity.x > 0:
			$Sprite2D.flip_h = false
		elif velocity.x < 0:
			$Sprite2D.flip_h = true


func process_normal_movement(delta):
	# --- Normal Movement Logic (Called when DashState.NONE) ---
	# Apply gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = jump_velocity

	# Get horizontal input
	var horizontal_input = Input.get_axis("ui_left", "ui_right")

	# Apply horizontal movement (velocity might be high from dash exit)
	if horizontal_input:
		velocity.x = horizontal_input * speed
	#else: # Friction is handled after the match statement now
		#velocity.x = move_toward(velocity.x, 0, speed)


# Helper to check for terrain overlap
func _check_overlap_with_dash_terrain() -> bool:
	var terrain_check_mask = (1 << (DASH_TERRAIN_LAYER - 1))
	var current_move_mask = get_collision_mask()
	# Ensure the check mask doesn't conflict during state transitions
	if current_dash_state == DashState.NONE:
		# If not dashing, use original mask logic might be safer,
		# but for this check, we *only* care about dash terrain layer.
		pass # Use the specific check mask below
	
	set_collision_mask(terrain_check_mask)
	var is_overlapping = test_move(global_transform, Vector2.ZERO)
	set_collision_mask(current_move_mask) # Restore actual movement mask
	return is_overlapping

# Helper to check for wall collision after move_and_slide
func _check_for_wall_collision() -> bool:
	var collision = get_last_slide_collision()
	if collision:
		var collider = collision.get_collider()
		# Using groups is preferred
		if collider and collider.is_in_group("walls"):
		# Alt: Check layer
		# if collider and collider.get_collision_layer_value(WALL_LAYER):
			return true
	return false


func _start_dash(h_input: float):
	if current_dash_state != DashState.NONE: return # Already dashing

	print("Starting dash (Initial Phase).")
	current_dash_state = DashState.INITIAL
	initial_dash_timer = initial_dash_duration # Start the timer
	dash_direction = Vector2(h_input, 0).normalized()

	# Store originals if needed (usually done in _ready)
	if original_collision_mask == 0: original_collision_mask = get_collision_mask()
	if original_collision_layer == 0: original_collision_layer = get_collision_layer()

	# Configure collision mask for dashing (Hit Walls, Ignore Terrain)
	var dash_movement_mask = original_collision_mask
	dash_movement_mask |= (1 << (WALL_LAYER - 1))
	dash_movement_mask &= ~(1 << (DASH_TERRAIN_LAYER - 1))
	set_collision_mask(dash_movement_mask)

	# Configure collision layer (optional: disable self-collision)
	set_collision_layer_value(PLAYER_LAYER, false)

	dash_cooldown_timer = dash_cooldown # Set cooldown duration


func _stop_dash(hit_wall: bool):
	if current_dash_state == DashState.NONE: return # Already stopped

	var previous_state = current_dash_state
	print("Stopping dash. Reason: %s" % ("Wall Collision" if hit_wall else "Timeout/Exit Terrain"))
	current_dash_state = DashState.NONE

	# Restore original collision settings
	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer)
	set_collision_layer_value(PLAYER_LAYER, true) # Ensure player layer is back ON

	# --- Handle Velocity ---
	if hit_wall:
		velocity = Vector2.ZERO # Stop dead on wall impact
	# else (Timeout or Exited Terrain):
	# DO NOTHING to velocity here. Keep the current dash velocity.
	# The normal movement logic after the 'match' statement will handle
	# applying gravity and friction to this remaining velocity.

# Input Map actions needed: "ui_left", "ui_right", "ui_up", "dash"
