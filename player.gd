extends CharacterBody2D

# Movement parameters
@export var speed = 300.0
@export var gravity = 800.0
@export var jump_velocity = -400.0
@export var dash_speed = 600.0
@export var dash_cooldown = 0.5
@export var initial_dash_duration = 0.15

# Death sequence parameters
@export var death_particle_scene: PackedScene # Assign your particle scene in the Inspector
@export var death_animation_duration = 0.8 # How long the death animation lasts
@export var blink_frequency = 10.0 # How fast to blink red (Hz)
@export var shake_intensity = 3.0 # How much to shake (pixels)

# Collision Layer Numbers
const PLAYER_LAYER = 1
const WALL_LAYER = 2
const DASH_TERRAIN_LAYER = 3
const LAVA_LAYER = 4

# --- Updated Dash States ---
enum DashState { NONE, INITIAL, TERRAIN, DYING }
var current_dash_state = DashState.NONE

var dash_direction = Vector2.ZERO
var dash_cooldown_timer = 0.0
var initial_dash_timer = 0.0

# --- Death State Variables ---
var death_timer = 0.0
var blink_accum = 0.0

var original_collision_mask: int
var original_collision_layer: int

# Node references
@onready var sprite = $Sprite2D2
@onready var collision_shape = $CollisionShape2D

func _ready():
	# Store original settings AFTER ensuring they are set correctly in the editor.
	# Make sure the player's Collision Mask in the Inspector includes Wall (2) and Lava (4).
	original_collision_mask = get_collision_mask()
	original_collision_layer = get_collision_layer()
	# Ensure player is on their designated layer
	set_collision_layer_value(PLAYER_LAYER, true)
	add_to_group("player") # Good for enemies finding the player

	if death_particle_scene == null:
		printerr("Death Particle Scene not assigned to player script!")


func _physics_process(delta):
	# --- Dash Cooldown ---
	if dash_cooldown_timer > 0 and current_dash_state == DashState.NONE:
		dash_cooldown_timer -= delta

	# --- Handle Dying State First ---
	if current_dash_state == DashState.DYING:
		process_dying(delta)
		return # Skip movement and other checks if dying

	# --- Update Velocity based on State ---
	match current_dash_state:
		DashState.NONE:
			process_normal_movement(delta)
			check_dash_input()

		DashState.INITIAL:
			process_initial_dash(delta) # Updates velocity, checks terrain/timeout

		DashState.TERRAIN:
			process_terrain_dash(delta) # Updates velocity, checks terrain exit

	# --- Apply Post-Dash Physics (if applicable) ---
	if current_dash_state == DashState.NONE:
		apply_post_dash_physics(delta)

	# --- Execute Movement ---
	move_and_slide()

	# --- Post-Movement Collision Checks ---
	# Order matters slightly: check hazards first, then dash-specific interactions
	if check_lava_collision(): # Check for lava collision
		die() # Trigger death if on lava
		return # Stop further processing if dead

	if is_dashing(): # Only check dash collisions if currently dashing
		check_dash_wall_collisions() # Checks for initial stop & terrain fatal hit

	# --- Final Updates ---
	# Sprite flipping (only if alive and not dashing)
	if current_dash_state == DashState.NONE:
		update_sprite_flip()


# --- State Processing Functions ---

func process_normal_movement(delta):
	if not is_on_floor(): velocity.y += gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor(): velocity.y = jump_velocity
	var horizontal_input = Input.get_axis("ui_left", "ui_right")
	if horizontal_input:
		$Sprite2D2.play("walking")
		velocity.x = horizontal_input * speed
	else:
		$Sprite2D2.stop()
	# Friction applied in apply_post_dash_physics

func check_dash_input():
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0:
		var h_input = Input.get_axis("ui_left", "ui_right")
		var v_input = Input.get_axis("ui_up", "ui_down")
		if h_input != 0 or v_input != 0:
			_start_dash()
			# Apply initial velocity immediately if dash started
			if current_dash_state != DashState.NONE:
				velocity = dash_direction * dash_speed

func process_initial_dash(delta):
	initial_dash_timer -= delta
	var is_in_terrain = _check_overlap_with_dash_terrain() # Check *before* moving

	if is_in_terrain:
		print("Initial dash entered terrain, extending.")
		current_dash_state = DashState.TERRAIN
		velocity = dash_direction * dash_speed # Maintain speed
	elif initial_dash_timer <= 0:
		print("Initial dash timed out.")
		_stop_dash(false) # Keep momentum
	else:
		# Still in initial dash, maintain velocity
		velocity = dash_direction * dash_speed
		# Collision check is now done *after* move_and_slide in _physics_process

func process_terrain_dash(delta):
	var is_in_terrain = _check_overlap_with_dash_terrain() # Check *before* moving

	if not is_in_terrain:
		print("Exited terrain during dash.")
		_stop_dash(false) # Keep momentum
	else:
		# Still in terrain, maintain velocity
		velocity = dash_direction * dash_speed
		# Wall collision check is now done *after* move_and_slide in _physics_process

func process_dying(delta):
	# Animation runs here, no movement input processed
	death_timer -= delta
	blink_accum += delta * blink_frequency
	var blink_val = (sin(blink_accum * PI * 2) + 1.0) / 2.0
	sprite.modulate = Color.WHITE.lerp(Color.RED, blink_val)
	sprite.offset = Vector2(randf_range(-shake_intensity, shake_intensity),
							randf_range(-shake_intensity, shake_intensity))
	if death_timer <= 0:
		sprite.modulate = Color.WHITE
		sprite.offset = Vector2.ZERO
		print("Restarting level...")
		get_tree().reload_current_scene()

func apply_post_dash_physics(delta):
	if not is_on_floor(): velocity.y += gravity * delta
	var horizontal_input_check = Input.get_axis("ui_left", "ui_right")
	if horizontal_input_check == 0: velocity.x = move_toward(velocity.x, 0, speed)

func update_sprite_flip():
	if velocity.x > 0: sprite.flip_h = false
	elif velocity.x < 0: sprite.flip_h = true

# --- Collision Check Functions ---

func check_lava_collision() -> bool:
	# Checks if any collision after move_and_slide was with something on the lava physics layer
	var collision_count = get_slide_collision_count()
	for i in range(collision_count):
		var collision = get_slide_collision(i)
		if collision:
			# Get the RID of the object collided with
			var collider_rid = collision.get_collider_rid()
			if collider_rid.is_valid(): # Make sure we have a valid physics object
				# Ask the PhysicsServer what collision layer the collided body belongs to
				var collider_layer_mask = PhysicsServer2D.body_get_collision_layer(collider_rid)

				# Check if the bit corresponding to LAVA_LAYER is set in the mask
				if (collider_layer_mask >> (LAVA_LAYER - 1)) & 1:
					print("Collision with Lava physics layer detected!")
					return true # Found lava collision
	return false # No lava collision found

func check_dash_wall_collisions():
	# Handles wall collision logic specifically during dashes
	# This function is only called if is_dashing() is true
	var collision_count = get_slide_collision_count()
	for i in range(collision_count):
		var collision = get_slide_collision(i)
		if collision:
			var collider = collision.get_collider() # Still need the node to check the group
			# Check if it's a wall (using group)
			if collider and collider.is_in_group("walls"):
				# --- Check if it's a fatal head-on collision during TERRAIN dash ---
				if current_dash_state == DashState.TERRAIN:
					var normal = collision.get_normal()
					var dot_product = dash_direction.dot(normal)
					var head_on_threshold = -0.7
					if dot_product < head_on_threshold:
						print(">>> CRITICAL HIT on Wall during Terrain Dash! <<<")
						die()
						return # Stop checking once dead

				# --- Check if it's *any* wall collision during INITIAL dash ---
				elif current_dash_state == DashState.INITIAL:
					print("Initial dash hit wall.")
					_stop_dash(true) # Stop the initial dash non-fatally
					# We assume stopping the dash is enough, don't need to check more collisions this frame
					return

# --- Helper Functions ---

func _check_overlap_with_dash_terrain() -> bool:
	# No changes needed here, but ensure it doesn't run if dying
	if current_dash_state == DashState.DYING: return false

	var terrain_check_mask = (1 << (DASH_TERRAIN_LAYER - 1))
	var current_move_mask = get_collision_mask()
	# Temporarily change mask to ONLY check for terrain overlap
	set_collision_mask(terrain_check_mask)
	# Use test_move on current position to see if overlapping
	var is_overlapping = test_move(global_transform, Vector2.ZERO)
	# IMPORTANT: Restore the original movement mask immediately
	set_collision_mask(current_move_mask)
	return is_overlapping

# --- Action Functions ---

func _start_dash():
	if current_dash_state != DashState.NONE: return
	var h_input = Input.get_axis("ui_left", "ui_right")
	var v_input = Input.get_axis("ui_up", "ui_down")
	var potential_direction = Vector2.ZERO
	if v_input != 0: potential_direction = Vector2(0, v_input)
	elif h_input != 0: potential_direction = Vector2(h_input, 0)
	else: return

	print("Starting dash (Initial Phase). Direction: ", potential_direction)
	current_dash_state = DashState.INITIAL
	initial_dash_timer = initial_dash_duration
	dash_direction = potential_direction.normalized()

	# Store original mask/layer if not already stored (safer)
	if original_collision_mask == 0: original_collision_mask = get_collision_mask()
	if original_collision_layer == 0: original_collision_layer = get_collision_layer()

	# Modify collision for dash movement
	var dash_movement_mask = original_collision_mask
	dash_movement_mask |= (1 << (WALL_LAYER - 1)) # Ensure wall collision
	dash_movement_mask &= ~(1 << (DASH_TERRAIN_LAYER - 1)) # Ignore terrain shape for movement
	dash_movement_mask |= (1 << (LAVA_LAYER - 1)) # Ensure lava collision

	set_collision_mask(dash_movement_mask)
	set_collision_layer_value(PLAYER_LAYER, false) # Become non-interactable on player layer

	dash_cooldown_timer = dash_cooldown


func _stop_dash(hit_wall: bool):
	if current_dash_state == DashState.DYING or current_dash_state == DashState.NONE: return

	var previous_state = current_dash_state
	print("Stopping dash. Reason: %s" % ("Wall Contact" if hit_wall else "Timeout/Exit Terrain"))
	current_dash_state = DashState.NONE

	# Restore original collision settings
	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer) # Restore full layer value
	set_collision_layer_value(PLAYER_LAYER, true) # Ensure player layer is active again

	if hit_wall and previous_state == DashState.INITIAL:
		# Stop dead only if initial dash hit a wall
		velocity = Vector2.ZERO
	# else: Keep momentum if timed out, exited terrain, or terrain dash scraped wall non-fatally


# --- PUBLIC DEATH FUNCTION ---
func die():
	# Check if already dying to prevent re-triggering
	if current_dash_state == DashState.DYING:
		return

	print("Player Died!")
	current_dash_state = DashState.DYING
	death_timer = death_animation_duration
	blink_accum = 0.0
	
	$Sprite2D2.play("dying")

	# Stop movement immediately
	velocity = Vector2.ZERO

	# Disable collision shape *during* death animation
	collision_shape.disabled = true

	# Restore original collision mask/layer immediately
	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer)
	set_collision_layer_value(PLAYER_LAYER, true)

	# Instantiate particles
	if death_particle_scene:
		var particles = death_particle_scene.instantiate()
		get_parent().add_child(particles) # Add to parent (scene root usually)
		particles.global_position = self.global_position

	# Play a sound? (Example)
	# if has_node("DeathSound"): $DeathSound.play()

# Public helper function
func is_dashing() -> bool:
	return current_dash_state == DashState.INITIAL or current_dash_state == DashState.TERRAIN
