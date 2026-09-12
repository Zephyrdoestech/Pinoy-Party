# autoload/SceneLoader.gd
extends Node

var _load_generation := 0

func go_to_minigame(minigame_id: String, players: Array[int]) -> void:
	_load_generation += 1
	var generation := _load_generation
	BgmManager.play_minigame()
	# Folders are PascalCase (LangitLupa, SackRace, LuksongBaka) but the
	# .tscn files on disk are snake_case (langit_lupa.tscn, sack_race.tscn,
	# luksong_baka.tscn). Build the path with to_snake_case() for the filename
	# only — the folder name stays PascalCase.
	var scene_file := minigame_id.to_snake_case()
	var path := "res://scenes/minigames/%s/%s.tscn" % [minigame_id, scene_file]
	var request_error := ResourceLoader.load_threaded_request(path, "PackedScene")
	if request_error != OK:
		push_error("[SceneLoader] Failed to request minigame scene '%s': error code %d" % [path, request_error])
		return
	var progress: Array = []
	while ResourceLoader.load_threaded_get_status(path, progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		if generation != _load_generation:
			return
	var load_status := ResourceLoader.load_threaded_get_status(path, progress)
	if load_status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("[SceneLoader] Failed loading minigame scene '%s': status %d" % [path, load_status])
		return
	var packed_scene := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed_scene == null or generation != _load_generation:
		push_error("[SceneLoader] Minigame resource was not a PackedScene: %s" % path)
		return
	var err := get_tree().change_scene_to_packed(packed_scene)
	if err != OK:
		push_error("[SceneLoader] Failed to load minigame scene '%s': error code %d" % [path, err])
		return
	call_deferred(&"_report_minigame_ready_deferred", minigame_id)

func _report_minigame_ready_deferred(minigame_id: String) -> void:
	# Two frames: the first lets the scene tree swap the root node,
	# the second lets the new scene's _ready() complete before we report ready.
	await get_tree().process_frame
	await get_tree().process_frame
	var minigame := get_tree().current_scene
	if minigame is BaseMinigame:
		NetworkManager.report_minigame_ready(minigame_id)
	else:
		push_error("SceneLoader: loaded scene is not a BaseMinigame. Got: %s" % minigame)

func start_loaded_minigame(players: Array[int]) -> void:
	var minigame := get_tree().current_scene
	if minigame is BaseMinigame:
		minigame.start_game(players)
	else:
		push_error("SceneLoader: cannot start unloaded minigame. Got: %s" % minigame)

func return_to_board() -> void:
	_load_generation += 1
	BgmManager.play_board()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
