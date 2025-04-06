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

# --- Updated Dash States ---
enum DashState { NONE, INITIAL, TERRAIN, DYING } # Added DYING state
var current_dash_state = DashState.NONE

var dash_direction = Vector2.ZERO
var dash_cooldown_timer = 0.0
var initial_dash_timer = 0.0

# --- Death State Variables ---
var death_timer = 0.0
var blink_accum = 0.0 # Accumulator for blinking effect

var original_collision_mask: int
var original_collision_layer: int

# Node references
@onready var sprite = $Sprite2D2
@onready var collision_shape = $CollisionShape2D # Assuming this is your shape node name

func _ready():
	original_collision_mask = get_collision_mask()
	original_collision_layer = get_collision_layer()
	set_collision_layer_value(PLAYER_LAYER, true)
	add_to_group("player")
	# Ensure particle scene is assigned
	if death_particle_scene == null:
		printerr("Death Particle Scene not assigned to player script!")


func _physics_process(delta):
	# --- Dash Cooldown ---
	# Cooldown only ticks when not dashing or dying
	if dash_cooldown_timer > 0 and (current_dash_state == DashState.NONE):
		dash_cooldown_timer -= delta

	# --- State Machine ---
	match current_dash_state:
		DashState.NONE:
			process_normal_movement(delta)
			check_dash_input() # Check input separately

		DashState.INITIAL:
			process_initial_dash(delta)

		DashState.TERRAIN:
			process_terrain_dash(delta) # Modified this function

		DashState.DYING:
			process_dying(delta) # Handle death animation

	# --- Final Movement Execution ---
	# Only move if not dying
	if current_dash_state != DashState.DYING:
		# Apply friction/gravity if dash just ended
		if current_dash_state == DashState.NONE:
			apply_post_dash_physics(delta)

		# Final move for the frame if normal movement occurred or dash ended normally
		# Prevent move_and_slide during death anim
		if current_dash_state != DashState.DYING:
			move_and_slide()

		# Sprite flipping (only if alive and not dashing)
		if current_dash_state == DashState.NONE:
			update_sprite_flip()

# --- State Processing Functions ---

func process_normal_movement(delta):
	if not is_on_floor(): velocity.y += gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor(): velocity.y = jump_velocity
	var horizontal_input = Input.get_axis("ui_left", "ui_right")
	if horizontal_input: velocity.x = horizontal_input * speed
	# Friction applied in apply_post_dash_physics

func check_dash_input():
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0:
		var h_input = Input.get_axis("ui_left", "ui_right")
		var v_input = Input.get_axis("ui_up", "ui_down")
		if h_input != 0 or v_input != 0:
			_start_dash()
			if current_dash_state != DashState.NONE:
				# Apply initial dash velocity immediately
				velocity = dash_direction * dash_speed
				# Don't move_and_slide here, let the state handler do it first

func process_initial_dash(delta):
	initial_dash_timer -= delta
	var is_in_terrain = _check_overlap_with_dash_terrain()

	if is_in_terrain:
		print("Initial dash entered terrain, extending.")
		current_dash_state = DashState.TERRAIN
		velocity = dash_direction * dash_speed # Ensure velocity is set for this frame
	elif initial_dash_timer <= 0:
		print("Initial dash timed out.")
		_stop_dash(false) # Keep momentum
	else:
		# Still in initial dash
		velocity = dash_direction * dash_speed
		# Need to move_and_slide before checking collision
		move_and_slide()
		if _check_for_wall_collision():
			_stop_dash(true) # Stop dash, hit wall

func process_terrain_dash(delta):
	var is_in_terrain = _check_overlap_with_dash_terrain()

	if not is_in_terrain:
		print("Exited terrain during dash.")
		_stop_dash(false) # Keep momentum
	else:
		# Still in terrain, move first
		velocity = dash_direction * dash_speed
		move_and_slide()

		# --- Check for Wall Collision - DEATH TRIGGER ---
		if _check_for_wall_collision():
			print(">>> CRITICAL HIT on Wall during Terrain Dash! <<<")
			_start_death_sequence() # Initiate death instead of just stopping
		# ---------------------------------------------

func process_dying(delta):
	# Animation runs here, no movement input processed
	death_timer -= delta

	# Blinking effect
	blink_accum += delta * blink_frequency
	var blink_val = (sin(blink_accum * PI * 2) + 1.0) / 2.0 # Value from 0 to 1
	sprite.modulate = Color.WHITE.lerp(Color.RED, blink_val)

	# Shaking effect (apply to sprite offset for visual-only shake)
	sprite.offset = Vector2(randf_range(-shake_intensity, shake_intensity),
							randf_range(-shake_intensity, shake_intensity))

	# Check if animation finished
	if death_timer <= 0:
		# Restore sprite appearance before restart
		sprite.modulate = Color.WHITE
		sprite.offset = Vector2.ZERO
		# Restart the level
		print("Restarting level...")
		get_tree().reload_current_scene()

func apply_post_dash_physics(delta):
	# Handles physics after dash ends (momentum preserved)
	if not is_on_floor(): velocity.y += gravity * delta
	var horizontal_input_check = Input.get_axis("ui_left", "ui_right")
	if horizontal_input_check == 0: velocity.x = move_toward(velocity.x, 0, speed)

func update_sprite_flip():
	if velocity.x > 0: sprite.flip_h = false
	elif velocity.x < 0: sprite.flip_h = true

# --- Helper Functions ---

func _check_overlap_with_dash_terrain() -> bool:
	# Prevent check if dying or already stopped
	if current_dash_state == DashState.DYING or current_dash_state == DashState.NONE:
		return false # Avoid mask changes in invalid states

	var terrain_check_mask = (1 << (DASH_TERRAIN_LAYER - 1))
	var current_move_mask = get_collision_mask()
	set_collision_mask(terrain_check_mask)
	var is_overlapping = test_move(global_transform, Vector2.ZERO)
	set_collision_mask(current_move_mask)
	return is_overlapping

func _check_for_wall_collision() -> bool:
	var collision = get_last_slide_collision()
	if collision:
		var collider = collision.get_collider()
		if collider and collider.is_in_group("walls"):
			return true
	return false

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

	if original_collision_mask == 0: original_collision_mask = get_collision_mask()
	if original_collision_layer == 0: original_collision_layer = get_collision_layer()

	var dash_movement_mask = original_collision_mask
	dash_movement_mask |= (1 << (WALL_LAYER - 1))
	dash_movement_mask &= ~(1 << (DASH_TERRAIN_LAYER - 1))
	set_collision_mask(dash_movement_mask)
	set_collision_layer_value(PLAYER_LAYER, false)
	dash_cooldown_timer = dash_cooldown

func _stop_dash(hit_wall: bool):
	# Don't stop if already dying
	if current_dash_state == DashState.DYING or current_dash_state == DashState.NONE: return

	var previous_state = current_dash_state
	print("Stopping dash. Reason: %s" % ("Wall Collision (non-fatal)" if hit_wall else "Timeout/Exit Terrain"))
	current_dash_state = DashState.NONE

	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer)
	set_collision_layer_value(PLAYER_LAYER, true)

	if hit_wall: velocity = Vector2.ZERO # Stop dead only on non-fatal wall hit
	# else: Keep momentum


func _start_death_sequence():
	# Prevent starting if already dying or not in terrain dash
	if current_dash_state != DashState.TERRAIN: return

	print("Starting Death Sequence!")
	current_dash_state = DashState.DYING
	death_timer = death_animation_duration # Start countdown
	blink_accum = 0.0 # Reset blink accumulator

	# Stop movement immediately
	velocity = Vector2.ZERO

	# Disable collision shape to prevent further physics interactions
	collision_shape.disabled = true

	# Restore original collision mask/layer immediately to prevent weirdness
	# Although shape is disabled, good practice.
	set_collision_mask(original_collision_mask)
	set_collision_layer(original_collision_layer)
	set_collision_layer_value(PLAYER_LAYER, true) # Re-enable player layer just in case

	# Instantiate particles
	if death_particle_scene:
		var particles = death_particle_scene.instantiate()
		# Add particles to the main scene tree, not the player itself
		get_parent().add_child(particles)
		particles.global_position = self.global_position # Position at player
		# The particle system should be configured as one-shot

	# Play a sound? (Example)
	# $DeathSound.play() # If you have an AudioStreamPlayer node

# Public helper function
func is_dashing() -> bool:
	return current_dash_state == DashState.INITIAL or current_dash_state == DashState.TERRAIN
