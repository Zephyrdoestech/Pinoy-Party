extends Node2D

const Utils = preload("res://scripts/utils.gd")

var player_index: int = 0
var board_ref: Node2D

signal movement_finished(player_index: int)

@onready var color_rect: ColorRect = $ColorRect

func setup(index: int, board: Node2D) -> void:
	player_index = index
	board_ref = board
	color_rect.color = GameManager.players[player_index]["color"]
	global_position = board_ref.get_tile_position(0) + Utils.token_offset(player_index)

func move_to(target_tile_index: int) -> void:
	if board_ref == null:
		return
	var current_idx: int = GameManager.players[player_index]["tile_index"]
	_step_toward(current_idx, target_tile_index)

func _step_toward(current_idx: int, target_idx: int) -> void:
	if current_idx >= target_idx:
		movement_finished.emit(player_index)
		return

	var next_idx: int = min(current_idx + 1, target_idx)
	var target_pos: Vector2 = board_ref.get_tile_position(next_idx) + Utils.token_offset(player_index)

	var tween := create_tween()
	tween.tween_property(self, "global_position", target_pos, Constants.MOVE_STEP_DURATION)
	tween.finished.connect(func():
		GameManager.players[player_index]["tile_index"] = next_idx
		_step_toward(next_idx, target_idx)
	)
