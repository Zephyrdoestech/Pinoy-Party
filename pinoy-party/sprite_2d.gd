extends Sprite2D

@export var speed := 150.0

func _process(delta: float) -> void:
	region_rect.position.x += speed * delta
