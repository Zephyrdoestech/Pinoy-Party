# autoload/SceneLoader.gd
extends Node

func go_to_minigame(minigame_id: String, players: Array[int]) -> void:
	var path := "res://scenes/minigames/%s/%s.tscn" % [minigame_id, minigame_id.to_snake_case()]
	print("[SceneLoader] Loading minigame scene: ", path)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[SceneLoader] Failed to load minigame scene '%s': error code %d" % [path, err])
		return
	call_deferred(&"_start_minigame_deferred", players)

func _start_minigame_deferred(players: Array[int]) -> void:
	print("[SceneLoader] _start_minigame_deferred called!")
	await get_tree().process_frame
	var minigame := get_tree().current_scene
	print("[SceneLoader] current_scene after deferred wait: ", minigame)
	if minigame is BaseMinigame:
		minigame.start_game(players)
	else:
		push_error("SceneLoader: loaded scene is not a BaseMinigame, cannot start_game(). Got: %s" % minigame)

func return_to_board() -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
