# scenes/minigames/BaseMinigame.gd
class_name BaseMinigame
extends Node2D

## Player indices participating (set externally before start_game(), or read here)
var participating_players: Array[int] = []

## Override in each minigame — called by SceneLoader after instancing
func start_game(players: Array[int]) -> void:
	participating_players = players

## Call this when the minigame is fully resolved.
## Emits through EventBus so State_TileEvent's await catches it.
func _finish(scores: Dictionary) -> void:
	EventBus.minigame_finished.emit(scores)
	await get_tree().create_timer(2.0).timeout
	SceneLoader.return_to_board()
