extends Node2D

@export var tile_scene: PackedScene = preload("res://scenes/board/Tile.tscn")

var tiles: Array[Node2D] = []

func _ready() -> void:	
	generate_board()

func generate_board() -> void:
	for child in get_children():
		child.queue_free()
	tiles.clear()

	for i in range(Constants.TOTAL_TILES):
		var tile_instance: Node2D = tile_scene.instantiate()
		add_child(tile_instance)
		tile_instance.position = Utils.tile_position(i)
		tile_instance.setup(i, _determine_tile_type(i))
		tiles.append(tile_instance)

func _determine_tile_type(index: int) -> int:
	if index == 0 or index == Constants.TOTAL_TILES - 1:
		return Enums.TileType.BLANK
	if index % 4 == 0:
		print("[Board] tile %d generated as GAME_TRIGGER" % index)
		return Enums.TileType.GAME_TRIGGER
	if index % 2 == 0 :
		print("[Board] tile %d generated as TRIVIA" % index)
		return Enums.TileType.TRIVIA
	return Enums.TileType.BLANK

func get_tile_position(index: int) -> Vector2:
	var clamped: int = clamp(index, 0, tiles.size() - 1)
	return tiles[clamped].global_position

func get_tile_type(index: int) -> int:
	var clamped: int = clamp(index, 0, tiles.size() - 1)
	print("[Board] get_tile_type(%d) → clamped=%d, returning %s"
		% [index, clamped, Enums.TileType.keys()[tiles[clamped].tile_type]])
	return tiles[clamped].tile_type
