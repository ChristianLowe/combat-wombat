extends AnimatedSprite2D

var base_position: Vector2
var elapsed: float = 0

@export var period: float = 1
@export var magnitude: float = 8

func _ready() -> void:
	base_position = self.position + Vector2.ZERO

func _process(delta: float) -> void:
	elapsed += delta
	self.position.y = base_position.y + magnitude * sin(2 * PI * elapsed / period)
	
