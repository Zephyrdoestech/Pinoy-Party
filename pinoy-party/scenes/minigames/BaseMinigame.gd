# scenes/minigames/BaseMinigame.gd
extends Node2D
class_name BaseMinigame

## All minigames emit this when done. scores = { player_index: points }
signal finished(scores: Dictionary)

## Override in each minigame
func start_game() -> void:
	pass

func _on_game_complete(scores: Dictionary) -> void:
	emit_signal("finished", scores)
	await get_tree().create_timer(2.0).timeout
	SceneLoader.return_to_board()
