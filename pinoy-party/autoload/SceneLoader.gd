# autoload/SceneLoader.gd
extends Node

func go_to_minigame(minigame_id: String, players: Array[int]) -> void:
	var path := "res://scenes/minigames/%s/%s.tscn" % [minigame_id, minigame_id.to_snake_case()]
	get_tree().change_scene_to_file(path)
	# Defer so the new scene's _ready() has already run before we call start_game()
	call_deferred(&"_start_minigame_deferred", players)

func _start_minigame_deferred(players: Array[int]) -> void:
	await get_tree().process_frame
	var minigame := get_tree().current_scene
	if minigame is BaseMinigame:
		minigame.start_game(players)
	else:
		push_error("SceneLoader: loaded scene is not a BaseMinigame, cannot start_game().")

func return_to_board() -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
