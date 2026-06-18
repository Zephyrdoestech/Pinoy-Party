# scripts/utils.gd
extends Node

## Returns a random minigame ID from the constants pool
static func random_minigame() -> String:
	return Constants.MINIGAMES[randi() % Constants.MINIGAMES.size()]

## Perimeter-loop board position for tile index.
## Walks clockwise starting top-left: right along top, down the right side,
## left along the bottom, up the left side back to start.
## Side lengths (edge count, corners shared/not double-counted):
##   top = Constants.TOP_TILES, right = Constants.SIDE_TILES,
##   bottom = Constants.TOP_TILES, left = Constants.SIDE_TILES
static func tile_position(index: int) -> Vector2:
	var top: int = Constants.TOP_TILES       # e.g. 9
	var side: int = Constants.SIDE_TILES     # e.g. 8
	var spacing: float = Constants.TILE_SPACING
	var origin: Vector2 = Vector2(50, 50)

	var i: int = index

	if i < top:
		# top edge, left to right
		return origin + Vector2(i * spacing, 0)
	i -= top

	if i < side:
		# right edge, top to bottom (starts one step down from top-right corner)
		return origin + Vector2((top - 1) * spacing, (i + 1) * spacing)
	i -= side

	if i < top:
		# bottom edge, right to left
		return origin + Vector2((top - 1 - i) * spacing, (side + 1) * spacing)
	i -= top

	# left edge, bottom to top (remaining tiles back up to start)
	return origin + Vector2(0, (side - i) * spacing)

## Token offset so players don't overlap on same tile
static func token_offset(player_index: int) -> Vector2:
	return Vector2(player_index * 12 - 18, -30)
