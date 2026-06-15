# scripts/utils.gd
extends Node

## Returns a random minigame ID from the constants pool
static func random_minigame() -> String:
	return Constants.MINIGAMES[randi() % Constants.MINIGAMES.size()]

## Snake-path board position for tile index
static func tile_position(index: int) -> Vector2:
	var row := index / Constants.TILES_PER_ROW
	var col := index % Constants.TILES_PER_ROW
	if row % 2 == 1:
		col = (Constants.TILES_PER_ROW - 1) - col
	return Vector2(col * Constants.TILE_SPACING + 50, row * Constants.TILE_SPACING + 50)

## Token offset so players don't overlap on same tile
static func token_offset(player_index: int) -> Vector2:
	return Vector2(player_index * 12 - 18, -30)
