@tool
extends Node2D

@export var tile_index: int = 0
@export var tile_type: Enums.TileType = Enums.TileType.BLANK:
	set(value):
		tile_type = value
		_update_visual()

@export_group("Textures")
@export var texture_blank: Texture2D
@export var texture_trivia: Texture2D
@export var texture_game: Texture2D

func _ready() -> void:
	_update_visual()

func _update_visual() -> void:
	var sprite = get_node_or_null("Sprite2D")
	
	if sprite == null:
		return
	
	match tile_type:
		Enums.TileType.GAME_TRIGGER:
			sprite.texture = texture_game
		Enums.TileType.TRIVIA:
			sprite.texture = texture_trivia
		_:
			sprite.texture = texture_blank
