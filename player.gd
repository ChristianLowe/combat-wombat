extends CharacterBody2D

# Movement parameters
@export var speed = 300.0
@export var gravity = 800.0
@export var jump_velocity = -400.0
@export var dash_speed = 600.0
@export var dash_cooldown = 0.5

# Collision Layer Numbers
const PLAYER_LAYER = 1
const WALL_LAYER = 2         # Normal walls - STOP dash
const DASH_TERRAIN_LAYER = 3 # Special terrain - Dash THROUGH

var is_dashing = false
var dash_direction = Vector2.ZERO
var dash_cooldown_timer = 0.0

var original_collision_mask: int
var original_collision_layer: int # Store original layer too

func _ready():
	original_collision_mask = get_collision_mask()
	original_collision_layer = get_collision_layer()
	# Ensure player is on its layer (can also be set in editor)
	set_collision_layer_value(PLAYER_LAYER, true)
	# Add player to a group for easier identification if needed elsewhere
	add_to_group("player")
	# Recommendation: Add your wall nodes to a "walls" group in the editor
	# Recommendation: Add your dash terrain nodes to a "dash_terrain" group

func _physics_process(delta):
	# --- Dash Cooldown ---
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

	# --- Dashing Logic ---
	if is_dashing:
		# 1. Check if we are currently overlapping Dash Terrain (Layer 3)
		#    Use a temporary mask for test_move that ONLY sees Layer 3.
		var terrain_check_mask = (1 << (DASH_TERRAIN_LAYER - 1)) # Mask with only bit 3 set
		var current_move_mask = get_collision_mask() # Store the mask used for actual movement
		set_collision_mask(terrain_check_mask) # Temporarily set mask for test_move
		var is_in_dash_terrain = test_move(global_transform, Vector2.ZERO)
		set_collision_mask(current_move_mask) # Restore the actual movement mask immediately!

		if not is_in_dash_terrain:
			# If we are no longer in the special terrain, stop the dash.
			print("Exited dash terrain, stopping dash.")
			_stop_dash()
			# Fall through to normal movement processing for this frame
		else:
			# 2. We are in dash terrain, so try to move
			velocity = dash_direction * dash_speed
			# No gravity during dash

			move_and_slide() # Use the dash movement mask (includes walls, excludes dash terrain)

			# 3. Check if the move resulted in a collision (e.g., hit a Wall)
			var collision = get_last_slide_collision()
			if collision:
				var collider = collision.get_collider()
				# Check if the collision was with something on the WALL_LAYER
				# Using groups is often more robust:
				if collider and collider.is_in_group("walls"):
				# Alternatively, check layer directly (less flexible):
				# if collider and collider.get_collision_layer_value(WALL_LAYER):
					print("Dash collided with wall, stopping dash.")
					_stop_dash()
					# Stop velocity immediately after hitting wall
					velocity = Vector2.ZERO
					# Optional: Slightly push away from wall based on collision normal
					# velocity = collision.get_remainder().slide(collision.get_normal()) * 0.5 # Example pushback
			# If still dashing after checks, return to skip normal movement logic
			if is_dashing:
				return

	# --- Normal Movement Logic (Only if NOT dashing) ---
	# (Same as before)
	if not is_on_floor():
		velocity.y += gravity * delta
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = jump_velocity

	var horizontal_input = Input.get_axis("ui_left", "ui_right")

	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0 and horizontal_input != 0:
		_start_dash(horizontal_input)
		if is_dashing: # Check if dash actually started
			velocity = dash_direction * dash_speed
			move_and_slide() # Execute move for the first frame of the dash
			return

	if horizontal_input:
		velocity.x = horizontal_input * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()

	if velocity.x > 0:
		$Sprite2D.flip_h = false
	elif velocity.x < 0:
		$Sprite2D.flip_h = true


func _start_dash(h_input: float):
	# Check if already dashing to prevent issues
	if is_dashing: return

	print("Starting dash.")
	is_dashing = true
	dash_direction = Vector2(h_input, 0).normalized()

	# --- Configure Collision for Dash ---
	# Store originals if not already done (belt-and-suspenders)
	if original_collision_mask == 0: original_collision_mask = get_collision_mask()
	if original_collision_layer == 0: original_collision_layer = get_collision_layer()

	# Set MASK for dashing: Collide with Walls (Layer 2), Ignore Dash Terrain (Layer 3)
	var dash_movement_mask = original_collision_mask
	dash_movement_mask |= (1 << (WALL_LAYER - 1))         # Ensure Wall layer bit is ON
	dash_movement_mask &= ~(1 << (DASH_TERRAIN_LAYER - 1)) # Ensure Dash Terrain layer bit is OFF
	set_collision_mask(dash_movement_mask)

	# Set LAYER for dashing: Optionally disable player's own layer interaction
	# This prevents player hitting *itself* or other players if layer 1 is in the mask
	set_collision_layer_value(PLAYER_LAYER, false)

	dash_cooldown_timer = dash_cooldown

func _stop_dash():
	# Check if not dashing already to prevent redundant calls
	if not is_dashing: return

	is_dashing = false
	# Restore original collision settings
	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer) # Restore entire original layer setup
	# Ensure the player layer is explicitly re-enabled if it was part of the original layer
	set_collision_layer_value(PLAYER_LAYER, true)

# --- Input Map actions needed: ---
# "ui_left", "ui_right", "ui_up", "dash"
