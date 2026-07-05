# scenes/ui/score_board.gd
extends Control

const BOARD_SIZE := Vector2(384, 256)
const BOARD_MARGIN := Vector2(20, 20)
const ROW_START := Vector2(78, 48)
const ROW_GAP := 8.0
const ROW_SIZE := Vector2(228, 42)
const BG_TEXTURE := preload("res://assets/board_assets/LeaderBoard/leaderboard_bg.png")
const ROW_TEXTURES := [
	preload("res://assets/board_assets/LeaderBoard/leaderboard_char1.png"),
	preload("res://assets/board_assets/LeaderBoard/leaderboard_char2.png"),
	preload("res://assets/board_assets/LeaderBoard/leaderboard_char3.png"),
	preload("res://assets/board_assets/LeaderBoard/leaderboard_char4.png"),
]

var rows_by_player: Dictionary = {}
var row_layer: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(BOARD_SIZE.x + BOARD_MARGIN.x)
	offset_top = BOARD_MARGIN.y
	offset_right = -BOARD_MARGIN.x
	offset_bottom = BOARD_MARGIN.y + BOARD_SIZE.y
	custom_minimum_size = BOARD_SIZE
	size = BOARD_SIZE

	var bg := TextureRect.new()
	bg.texture = BG_TEXTURE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	row_layer = Control.new()
	row_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	row_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row_layer)

	EventBus.score_changed.connect(_on_score_changed)
	EventBus.turn_started.connect(_on_turn_started)
	_rebuild_rows()

func _rebuild_rows() -> void:
	for child in row_layer.get_children():
		child.queue_free()

	rows_by_player.clear()

	var active_indices := _get_active_player_indices()
	active_indices.sort_custom(func(a: int, b: int) -> bool:
		var score_a: int = GameManager.players[a]["score"]
		var score_b: int = GameManager.players[b]["score"]
		if score_a == score_b:
			return a < b
		return score_a > score_b
	)

	for rank in active_indices.size():
		var player_index: int = active_indices[rank]
		var row := _create_row(player_index)
		row.position = ROW_START + Vector2(0, rank * (ROW_SIZE.y + ROW_GAP))
		row_layer.add_child(row)

		rows_by_player[player_index] = {
			"marker": row.get_node("TurnMarker"),
			"score": row.get_node("ScoreLabel"),
		}

	_update_turn_marker(GameManager.current_player_index)

func _get_active_player_indices() -> Array[int]:
	var indices: Array[int] = []
	var count: int = min(min(GameManager.active_player_count, GameManager.players.size()), ROW_TEXTURES.size())
	for i in count:
		indices.append(i)
	return indices

func _create_row(player_index: int) -> Control:
	var row := Control.new()
	row.custom_minimum_size = ROW_SIZE
	row.size = ROW_SIZE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var texture := TextureRect.new()
	texture.texture = ROW_TEXTURES[player_index]
	texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture.stretch_mode = TextureRect.STRETCH_KEEP
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texture)

	var marker := Label.new()
	marker.name = "TurnMarker"
	marker.position = Vector2(-20, 9)
	marker.size = Vector2(18, 24)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 18)
	marker.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	row.add_child(marker)

	var name_label := Label.new()
	name_label.position = Vector2(47, 4)
	name_label.size = Vector2(112, 34)
	name_label.text = GameManager.players[player_index]["name"]
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.name = "ScoreLabel"
	score_label.position = Vector2(158, 4)
	score_label.size = Vector2(58, 34)
	score_label.text = str(GameManager.players[player_index]["score"])
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	score_label.add_theme_constant_override("shadow_offset_x", 1)
	score_label.add_theme_constant_override("shadow_offset_y", 1)
	row.add_child(score_label)

	return row

func _on_score_changed(player_index: int, _new_score: int) -> void:
	if player_index < 0 or player_index >= GameManager.active_player_count:
		return
	_rebuild_rows()

func _on_turn_started(current_player_index: int) -> void:
	_update_turn_marker(current_player_index)

func _update_turn_marker(current_player_index: int) -> void:
	for player_index in rows_by_player:
		var marker: Label = rows_by_player[player_index]["marker"]
		marker.text = ">" if player_index == current_player_index else ""
