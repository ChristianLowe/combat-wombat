extends Camera2D

@export var desired_width_px : float = 800

func _process(delta: float) -> void:
	var zoom = self.get_viewport_rect().size.x / desired_width_px 
	self.zoom.x = zoom
	self.zoom.y = zoom
