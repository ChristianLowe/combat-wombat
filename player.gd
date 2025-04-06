extends CharacterBody2D

# Movement parameters
@export var speed = 300.0
@export var gravity = 800.0
@export var jump_velocity = -400.0
@export var dash_speed = 600.0
@export var initial_dash_duration = 0.15 # Used for non-downward dash timeout

# --- Dash Resource ---
@export var max_dashes: int = 1
var dashes_available: int

# --- Downward Dash Flag ---
var is_down_dash: bool = false

# Death sequence parameters
@export var death_particle_scene: PackedScene
@export var death_animation_duration = 0.8
@export var blink_frequency = 10.0
@export var shake_intensity = 3.0

# Collision Layer Numbers
const PLAYER_LAYER = 1
const WALL_LAYER = 2
const DASH_TERRAIN_LAYER = 3
const LAVA_LAYER = 4
const ENEMY_LAYER = 5 # Make sure this matches your enemy's layer

# --- Dash States ---
enum DashState { NONE, INITIAL, TERRAIN, DYING }
var current_dash_state = DashState.NONE

var dash_direction = Vector2.ZERO
var initial_dash_timer = 0.0

# --- Death State Variables ---
var death_timer = 0.0
var blink_accum = 0.0

# Collision Mask/Layer Cache
var original_collision_mask: int
var original_collision_layer: int

# --- Landing Detection ---
var was_on_floor: bool = false

# Node references
@onready var sprite = $Sprite2D2
@onready var collision_shape = $CollisionShape2D
@onready var dash_hitbox_area = $DashHitboxArea # Area2D for detecting dash-through hits

#-----------------------------------------------------------------------------#
# Built-in Godot Functions                                                    #
#-----------------------------------------------------------------------------#

func _ready():
	# Store original collision settings from editor
	original_collision_mask = get_collision_mask()
	original_collision_layer = get_collision_layer()

	# Ensure player is on its designated layer and in group
	set_collision_layer_value(PLAYER_LAYER, true)
	add_to_group("player")

	# Initialize dash resource
	dashes_available = max_dashes

	# Initialize floor state for landing detection
	was_on_floor = is_on_floor()
	if was_on_floor:
		regain_dash() # Ensure dash available if starting grounded

	# Check for required exported scene
	if death_particle_scene == null:
		printerr("Death Particle Scene not assigned to player script!")

	# Setup the Area2D used for detecting dash-through hits
	if dash_hitbox_area:
		# Set what the hitbox area detects (enemies)
		dash_hitbox_area.set_collision_mask_value(ENEMY_LAYER, true)
		# Ensure it's not on any layer itself (doesn't need to BE detected)
		dash_hitbox_area.collision_layer = 0
		# Connect its signal to our handler function
		dash_hitbox_area.body_entered.connect(_on_dash_hitbox_area_body_entered)
		# Ensure it starts disabled (should also be set in editor process mode)
		dash_hitbox_area.monitoring = false
	else:
		printerr("Player scene missing required child node: DashHitboxArea!")


func _physics_process(delta):
	# --- Handle Dying State First ---
	if current_dash_state == DashState.DYING:
		process_dying(delta)
		return # Skip everything else if dying

	# --- Landing Detection ---
	var currently_on_floor = is_on_floor()
	if currently_on_floor and not was_on_floor:
		print("Player landed.")
		regain_dash() # Regain dash resource upon landing

	# --- Update Velocity based on State ---
	match current_dash_state:
		DashState.NONE:
			process_normal_movement(delta)
			check_dash_input()
		DashState.INITIAL:
			process_initial_dash(delta)
		DashState.TERRAIN:
			process_terrain_dash(delta)

	# --- Apply Post-Dash Physics (Friction/Gravity if needed) ---
	if current_dash_state == DashState.NONE:
		apply_post_dash_physics(delta)

	# --- Execute Movement ---
	move_and_slide()

	# --- Post-Movement Collision Checks ---
	# Check hazards resulting from movement first
	if check_lava_collision():
		die()
		return # Skip other checks if dead

	# Check for wall collisions resulting from movement *if* dashing
	if is_dashing():
		check_dash_wall_collisions() # Checks only walls now

	# --- Final Updates ---
	# Update sprite direction if not dashing
	if current_dash_state == DashState.NONE:
		update_sprite_flip()

	# Update floor state for next frame's landing check
	was_on_floor = currently_on_floor

#-----------------------------------------------------------------------------#
# State Processing Functions                                                  #
#-----------------------------------------------------------------------------#

func process_normal_movement(delta):
	# Apply gravity if in the air
	if not is_on_floor():
		velocity.y += gravity * delta

	# Handle jumping
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Handle horizontal movement input
	var horizontal_input = Input.get_axis("ui_left", "ui_right")
	velocity.x = horizontal_input * speed
	
	if horizontal_input:
		$Sprite2D2.play("walking")
	else:
		$Sprite2D2.stop()
	# Friction applied in apply_post_dash_physics

func check_dash_input():
	# Check if player can dash (has dashes available) and presses dash
	if Input.is_action_just_pressed("dash") and dashes_available > 0:
		# Check for directional input
		var h_input = Input.get_axis("ui_left", "ui_right")
		var v_input = Input.get_axis("ui_up", "ui_down")
		if h_input != 0 or v_input != 0:
			_start_dash() # Initiate the dash
			# Apply initial velocity immediately if dash started successfully
			if current_dash_state != DashState.NONE:
				velocity = dash_direction * dash_speed

func process_initial_dash(delta):
	# --- Downward Dash Special Logic ---
	if is_down_dash:
		# Continue downward dash velocity
		velocity = dash_direction * dash_speed
		# Stop condition (hitting floor) handled by check_dash_wall_collisions or landing check
		if is_on_floor(): # Backup check
			_stop_dash(false)
		return # Skip normal initial dash timeout/terrain checks

	# --- Normal Initial Dash Logic (Non-Downward) ---
	initial_dash_timer -= delta
	var is_in_terrain = _check_overlap_with_dash_terrain()

	if is_in_terrain:
		# Transition to terrain dash state
		print("Initial dash entered terrain, extending.")
		current_dash_state = DashState.TERRAIN
		velocity = dash_direction * dash_speed # Maintain speed
	elif initial_dash_timer <= 0:
		# Initial dash time ran out
		print("Initial dash timed out.")
		_stop_dash(false) # Stop dash, keep momentum
	else:
		# Still in initial dash, maintain velocity
		velocity = dash_direction * dash_speed
		# Wall collision checks happen after move_and_slide

func process_terrain_dash(delta):
	# --- Downward Dash Special Logic ---
	if is_down_dash:
		# Continue downward dash velocity while in terrain
		velocity = dash_direction * dash_speed
		# Stop condition (hitting floor) handled by check_dash_wall_collisions or landing check
		if is_on_floor(): # Backup check
			_stop_dash(false)
		return # Skip normal terrain exit checks

	# --- Normal Terrain Dash Logic (Non-Downward) ---
	var is_in_terrain = _check_overlap_with_dash_terrain()

	if not is_in_terrain:
		# Exited terrain
		print("Exited terrain during dash.")
		# Stop dash, indicating terrain involvement for dash regain
		_stop_dash(false, true) # Keep momentum, dashed_through_terrain = true
	else:
		# Still in terrain, maintain velocity
		velocity = dash_direction * dash_speed
		# Wall collision checks happen after move_and_slide

func process_dying(delta):
	# Handles death animation (blinking, shaking) and level restart
	death_timer -= delta
	blink_accum += delta * blink_frequency
	var blink_val = (sin(blink_accum * PI * 2) + 1.0) / 2.0 # 0 to 1 sine wave
	sprite.modulate = Color.WHITE.lerp(Color.RED, blink_val) # Blink red
	# Apply screenshake via sprite offset (visual only)
	sprite.offset = Vector2(randf_range(-shake_intensity, shake_intensity),
							randf_range(-shake_intensity, shake_intensity))

	# Check if death animation timer finished
	if death_timer <= 0:
		# Reset visual effects before restarting
		sprite.modulate = Color.WHITE
		sprite.offset = Vector2.ZERO
		print("Restarting level...")
		get_tree().reload_current_scene() # Restart the current scene

#-----------------------------------------------------------------------------#
# Physics & Movement Helpers                                                  #
#-----------------------------------------------------------------------------#

func apply_post_dash_physics(delta):
	# Apply gravity when not dashing and in air
	if not is_on_floor():
		velocity.y += gravity * delta
	# Apply friction if no horizontal input when not dashing
	var horizontal_input_check = Input.get_axis("ui_left", "ui_right")
	if horizontal_input_check == 0:
		velocity.x = move_toward(velocity.x, 0, speed) # Apply friction towards zero

func update_sprite_flip():
	# Flip sprite based on horizontal velocity
	if velocity.x > 0:
		sprite.flip_h = false
	elif velocity.x < 0:
		sprite.flip_h = true

#-----------------------------------------------------------------------------#
# Collision Check Functions                                                   #
#-----------------------------------------------------------------------------#

func check_lava_collision() -> bool:
	# Checks if any collision reported by move_and_slide involved lava layer
	var collision_count = get_slide_collision_count()
	for i in range(collision_count):
		var collision = get_slide_collision(i)
		if collision:
			var collider_rid = collision.get_collider_rid() # Use PhysicsServer for TileMap compatibility
			if collider_rid.is_valid():
				var collider_layer_mask = PhysicsServer2D.body_get_collision_layer(collider_rid)
				# Check if the Lava layer bit is set
				if (collider_layer_mask >> (LAVA_LAYER - 1)) & 1:
					print("Collision with Lava physics layer detected!")
					return true # Lava collision detected
	return false # No lava collision detected

func check_dash_wall_collisions():
	# Checks for wall collisions after move_and_slide *only* when dashing
	var collision_count = get_slide_collision_count()
	for i in range(collision_count):
		var collision = get_slide_collision(i)
		if collision:
			var collider = collision.get_collider()
			if not collider: continue # Skip if collider is somehow null

			# --- Check ONLY for Wall Collision ---
			if collider.is_in_group("walls"):
				var normal = collision.get_normal()
				var dot_product = dash_direction.dot(normal)
				var head_on_threshold = -0.7
				var is_head_on = dot_product < head_on_threshold

				# Stop downward dash if it hits a side wall
				if is_down_dash and abs(normal.x) > 0.9:
					print("Downward dash hit side wall.")
					_stop_dash(true) # Stop dash, hit wall
					return # Stop checking collisions

				# Trigger death if terrain dash hits wall head-on
				if current_dash_state == DashState.TERRAIN and is_head_on:
					print(">>> CRITICAL HIT on Wall during Terrain Dash! <<<")
					die()
					return # Stop checking collisions

				# Stop initial dash if it hits *any* wall non-fatally
				elif current_dash_state == DashState.INITIAL:
					print("Initial dash hit wall.")
					_stop_dash(true) # Stop dash, hit wall
					return # Stop checking collisions

			# --- Backup check: Stop downward dash if it hits floor ---
			# This catches cases where move_and_slide stops exactly on the floor
			elif is_down_dash and is_on_floor():
				print("Downward dash hit floor (detected in wall checks).")
				_stop_dash(false) # Stop dash, didn't hit a wall per se
				return # Stop checking collisions

#-----------------------------------------------------------------------------#
# Helper Functions                                                            #
#-----------------------------------------------------------------------------#

func _check_overlap_with_dash_terrain() -> bool:
	# Uses test_move to check if currently overlapping dash terrain layer
	# Important: This modifies the collision mask temporarily
	if current_dash_state == DashState.DYING: return false # Don't check if dying

	var terrain_check_mask = (1 << (DASH_TERRAIN_LAYER - 1)) # Mask for only terrain layer
	var current_move_mask = get_collision_mask() # Store current mask

	set_collision_mask(terrain_check_mask) # Temporarily change mask
	var is_overlapping = test_move(global_transform, Vector2.ZERO) # Check overlap at current pos
	set_collision_mask(current_move_mask) # Restore original mask immediately

	return is_overlapping

#-----------------------------------------------------------------------------#
# Action Functions                                                            #
#-----------------------------------------------------------------------------#

func _start_dash():
	# Dash availability check moved to check_dash_input
	# Consume dash resource
	dashes_available -= 1
	print("Dash used. Available: ", dashes_available)

	# Determine dash direction based on input
	var h_input = Input.get_axis("ui_left", "ui_right")
	var v_input = Input.get_axis("ui_up", "ui_down")
	var potential_direction = Vector2.ZERO

	# Determine direction (prioritize vertical?)
	if v_input != 0:
		potential_direction = Vector2(0, v_input).normalized()
		is_down_dash = (v_input > 0) # Set flag if dashing down
	elif h_input != 0:
		potential_direction = Vector2(h_input, 0).normalized()
		is_down_dash = false # Not a downward dash
	else:
		# Refund dash and cancel if no direction
		dashes_available = min(dashes_available + 1, max_dashes)
		print("Dash cancelled, no direction input.")
		return

	# --- Start of Nudge Logic ---
	if is_down_dash:
		var wall_check_distance = 1.0 # How far to check for wall (pixels)
		var nudge_amount = 0.1      # How far to nudge (pixels)
		var wall_mask = 1 << (WALL_LAYER - 1) # Mask for checking walls only

		# Check for wall immediately to the left using test_move
		# test_move(transform, motion, collision_result, margin, mask)
		if test_move(global_transform, Vector2(-wall_check_distance, 0), null, 0.0, wall_mask):
			print("DEBUG: Player against left wall during down dash start. Nudging right.")
			global_position.x += nudge_amount
		# Check for wall immediately to the right
		elif test_move(global_transform, Vector2(wall_check_distance, 0), null, 0.0, wall_mask):
			print("DEBUG: Player against right wall during down dash start. Nudging left.")
			global_position.x -= nudge_amount
	# --- End of Nudge Logic ---


	print("Starting dash. Direction: ", potential_direction, " Down Dash: ", is_down_dash)
	current_dash_state = DashState.INITIAL
	initial_dash_timer = initial_dash_duration
	dash_direction = potential_direction

	# Cache original collision settings if not already done (safety)
	if original_collision_mask == 0: original_collision_mask = get_collision_mask()
	if original_collision_layer == 0: original_collision_layer = get_collision_layer()

	# Set collision mask specifically for dashing movement
	var dash_movement_mask = original_collision_mask
	dash_movement_mask |= (1 << (WALL_LAYER - 1))           # Ensure collision with Walls
	dash_movement_mask &= ~(1 << (DASH_TERRAIN_LAYER - 1)) # Ignore Dash Terrain physically
	dash_movement_mask |= (1 << (LAVA_LAYER - 1))           # Ensure collision with Lava
	dash_movement_mask &= ~(1 << (ENEMY_LAYER - 1))        # Ignore Enemies physically

	set_collision_mask(dash_movement_mask) # Apply the calculated mask

	# Activate the Area2D used to detect passing through enemies
	if dash_hitbox_area:
		dash_hitbox_area.monitoring = true
		print("Dash hitbox activated.")


func _stop_dash(hit_wall: bool, dashed_through_terrain: bool = false):
	# Prevent stopping if already stopped or dying
	if current_dash_state == DashState.DYING or current_dash_state == DashState.NONE:
		return

	print("Stopping dash. Reason: %s" % ("Wall Contact" if hit_wall else ("Exited Terrain" if dashed_through_terrain else "Timeout/Floor/Other")))

	# Reset state and flags
	current_dash_state = DashState.NONE
	is_down_dash = false # Always reset downward dash flag when stopping

	# Deactivate the dash hitbox Area2D
	if dash_hitbox_area:
		dash_hitbox_area.monitoring = false
		print("Dash hitbox deactivated.")

	# Restore the original collision mask
	set_collision_mask(original_collision_mask)

	# Regain dash resource ONLY if stopping because terrain was involved
	if dashed_through_terrain:
		print("Regaining dash from terrain.")
		regain_dash()

	# Stop velocity only if initial dash hit a wall (optional based on feel)
	# Check previous state if needed, for now just checks hit_wall flag
	if hit_wall: # previous_state == DashState.INITIAL and hit_wall:
		velocity = Vector2.ZERO


func die():
	# Public function to initiate the death sequence
	if current_dash_state == DashState.DYING:
		return # Already dying

	print("Player Died!")
	current_dash_state = DashState.DYING
	death_timer = death_animation_duration
	blink_accum = 0.0 # Reset blink effect
	
	$Sprite2D2.play("dying")

	velocity = Vector2.ZERO # Stop all movement

	# Disable physics interaction during death animation
	collision_shape.disabled = true
	# Restore original collision settings just in case
	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer)
	set_collision_layer_value(PLAYER_LAYER, true)

	# Spawn death particles if scene is assigned
	if death_particle_scene:
		var particles = death_particle_scene.instantiate()
		# Add particles to the main scene tree, not the player itself
		get_parent().add_child(particles)
		particles.global_position = self.global_position # Position at player center

#-----------------------------------------------------------------------------#
# Dash Hitbox Signal Handler                                                  #
#-----------------------------------------------------------------------------#

func _on_dash_hitbox_area_body_entered(body):
	# Called when the DashHitboxArea overlaps a physics body
	# Only process this interaction if currently dashing
	if not is_dashing():
		return

	# Check if the overlapping body is an enemy
	if body.is_in_group("enemies"):
		print("Dash hitbox detected enemy: ", body.name)
		# Check if the enemy script has the function to handle the hit
		if body.has_method("handle_dash_hit"):
			body.handle_dash_hit() # Tell the enemy script it was hit
			regain_dash() # Regain dash resource for hitting the enemy
			# Dash continues through the enemy
		else:
			printerr("Enemy node ", body.name, " is missing 'handle_dash_hit' method!")

#-----------------------------------------------------------------------------#
# Public Functions & Helpers                                                  #
#-----------------------------------------------------------------------------#

func is_dashing() -> bool:
	# Helper to check if currently in any dashing state
	return current_dash_state == DashState.INITIAL or current_dash_state == DashState.TERRAIN

func regain_dash():
	# Increases available dashes, up to the maximum
	if dashes_available < max_dashes:
		dashes_available += 1
		print("Dash regained! Available: ", dashes_available)
		# TODO: Add optional visual/audio feedback here
	# else: print("Dash regain ignored, already at max.") # Optional debug
