# autoload/SceneLoader.gd
extends Node

func go_to_minigame(minigame_id: String, players: Array[int]) -> void:
	BgmManager.play_minigame()
	# Folders are PascalCase (LangitLupa, SackRace, LuksongBaka) but the
	# .tscn files on disk are snake_case (langit_lupa.tscn, sack_race.tscn,
	# luksong_baka.tscn). Build the path with to_snake_case() for the filename
	# only — the folder name stays PascalCase.
	var scene_file := minigame_id.to_snake_case()
	var path := "res://scenes/minigames/%s/%s.tscn" % [minigame_id, scene_file]
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[SceneLoader] Failed to load minigame scene '%s': error code %d" % [path, err])
		return
	call_deferred(&"_start_minigame_deferred", players)

func _start_minigame_deferred(players: Array[int]) -> void:
	# Two frames: the first lets the scene tree swap the root node,
	# the second lets the new scene's _ready() complete before we call into it.
	await get_tree().process_frame
	await get_tree().process_frame
	var minigame := get_tree().current_scene
	if minigame is BaseMinigame:
		minigame.start_game(players)
	else:
		push_error("SceneLoader: loaded scene is not a BaseMinigame, cannot start_game(). Got: %s" % minigame)

func return_to_board() -> void:
	BgmManager.play_board()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
