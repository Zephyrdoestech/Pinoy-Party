extends Node

const GAME_DEFAULT_BGM := preload("res://assets/bgm/game_default_bgm.mp3")
const BOARD_BGM := preload("res://assets/bgm/board_bgm.mp3")
const MINIGAME_BGM := preload("res://assets/bgm/minigame_bgm.mp3")
const TRIVIA_BGM := preload("res://assets/bgm/trivia_bgm.mp3")
const GAME_OVER_BGM_PATH := "res://assets/bgm/game_over_bgm.mp3"

var _player: AudioStreamPlayer
var _current_stream: AudioStream

func _ready() -> void:
	_ensure_player()

func _ensure_player() -> void:
	if _player != null:
		return
	_player = AudioStreamPlayer.new()
	_player.name = "BgmPlayer"
	add_child(_player)

func play_default() -> void:
	_play_bgm(GAME_DEFAULT_BGM)

func play_board() -> void:
	_play_bgm(BOARD_BGM)

func play_minigame() -> void:
	_play_bgm(MINIGAME_BGM)

func play_trivia() -> void:
	_play_bgm(TRIVIA_BGM)

func play_game_over() -> void:
	if ResourceLoader.exists(GAME_OVER_BGM_PATH):
		_play_bgm(load(GAME_OVER_BGM_PATH) as AudioStream)
	else:
		_play_bgm(GAME_DEFAULT_BGM)

func stop() -> void:
	if _player != null:
		_player.stop()
	_current_stream = null

func _play_bgm(stream: AudioStream) -> void:
	if stream == null:
		return
	_ensure_player()
	if _current_stream == stream and _player.playing:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_player.stop()
	_player.stream = stream
	_current_stream = stream
	_player.play()
