extends Node2D

var tile_index: int = 0
var tile_type: int = Enums.TileType.BLANK

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label

func setup(index: int, type: int) -> void:
	tile_index = index
	tile_type = type
	_update_visual()

func _update_visual() -> void:
	if color_rect == null:
		return
	match tile_type:
		Enums.TileType.GAME_TRIGGER:
			color_rect.color = Color.WEB_MAROON  # red
		Enums.TileType.TRIVIA:
			color_rect.color = Color.GOLDENROD
		_:
			color_rect.color = Color(0.7, 0.7, 0.7)  # gray
	if label:
		label.text = str(tile_index)
