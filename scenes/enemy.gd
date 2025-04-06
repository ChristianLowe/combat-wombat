extends CharacterBody2D

@export var speed: float = 150.0
@export var stun_duration: float = 5.0
@export var stun_flip_interval: float = 0.5

# Collision Layers (ensure these match your project settings)
const WALL_LAYER = 2
const ENEMY_LAYER = 5 # Assign a layer for enemies if you haven't

# Enemy States
enum State { NORMAL, STUNNED }
var current_state = State.NORMAL

# Timers
var stun_timer = 0.0
var stun_flip_timer = 0.0

# Movement
var direction = 1 # 1 for right, -1 for left
# Removed velocity here, will set directly in _physics_process when NORMAL

@onready var sprite = $Sprite2D # Or $AnimatedSprite2D if you used that
@onready var detection_area = $DetectionArea

func _ready():
	add_to_group("enemies")
	set_collision_layer_value(ENEMY_LAYER, true)
	set_collision_mask_value(WALL_LAYER, true)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	else:
		printerr("Enemy scene missing DetectionArea node!")

func _physics_process(delta):
	match current_state:
		State.NORMAL:
			process_normal_movement(delta)
			update_sprite_flip() # Update horizontal flip only when normal

		State.STUNNED:
			process_stunned(delta)

func process_normal_movement(delta):
	# Apply horizontal movement
	velocity = Vector2(direction * speed, 0)

	# Apply movement and check for wall collisions
	move_and_slide()
	check_wall_collisions()

func process_stunned(delta):
	# Stop movement while stunned
	velocity = Vector2.ZERO
	# Need to call move_and_slide even with zero velocity
	# to properly detect things entering the Area2D if needed,
	# or handle grounding if gravity were involved.
	move_and_slide()

	# Stun Timer
	stun_timer -= delta
	if stun_timer <= 0:
		_unstun()
		return # Exit processing for this frame as state changed

	# Vertical Flip Timer
	stun_flip_timer -= delta
	if stun_flip_timer <= 0:
		sprite.flip_v = not sprite.flip_v # Flip vertically
		stun_flip_timer = stun_flip_interval # Reset flip timer

func check_wall_collisions():
	# Check if the enemy hit a wall and needs to reverse
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		if collision:
			if abs(collision.get_normal().x) > 0.9:
				direction *= -1
				global_position += collision.get_normal() * 0.5
				break

func update_sprite_flip():
	# Horizontal flip based on movement direction (only when NORMAL)
	if direction > 0:
		sprite.flip_h = false
	elif direction < 0:
		sprite.flip_h = true
func _on_detection_area_body_entered(body):
	# Simplified: Only triggers if player is NOT dashing and enemy is NORMAL
	print(body.name, " entered ", self.name, "'s detection area.")

	# Ignore collisions if enemy is already stunned
	if current_state == State.STUNNED:
		print("Enemy is stunned, ignoring interaction.")
		return

	if body.is_in_group("player"):
		print("Detected body is player.")
		var player = body

		# Basic safety checks
		if not player.has_method("is_dashing") or not player.has_method("die"):
			printerr("Player node missing required methods (is_dashing/die)")
			return

		# ONLY handle the case where a non-dashing player touches a normal enemy
		if not player.is_dashing():
			print("Attempting to make non-dashing player die...")
			player.die()
		# else: Dashing player interaction is now handled by the player's check_dash_interactions
	else:
		print("Detected body is not in 'player' group.")


func _stun():
	# (No changes needed here unless you want visual/audio feedback)
	if current_state == State.STUNNED: return
	print("Enemy stunned!")
	current_state = State.STUNNED
	stun_timer = stun_duration
	stun_flip_timer = stun_flip_interval
	velocity = Vector2.ZERO
	sprite.flip_v = false


func _unstun():
	# (No changes needed here)
	print("Enemy unstunned.")
	current_state = State.NORMAL
	stun_timer = 0.0
	sprite.flip_v = false


# --- NEW FUNCTION ---
func handle_dash_hit():
	# This is called by the player script when a dash collides with this enemy
	print(self.name, " received dash hit.")
	_stun() # Trigger the stun state
