# autoload/SceneLoader.gd
extends Node

signal scene_loaded

func go_to_minigame(minigame_id: String) -> void:
	var path := "res://scenes/minigames/%s/%s.tscn" % [minigame_id, minigame_id]
	get_tree().change_scene_to_file(path)

func return_to_board() -> void:
	get_tree().change_scene_to_file("res://scenes/board/Board.tscn")
