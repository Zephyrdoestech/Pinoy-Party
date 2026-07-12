extends Control

const LOBBY_SCENE_PATH := "res://scenes/ui/LobbyScreen.tscn"
const HOVER_SFX := preload("res://assets/sfx/hover_sfx.mp3")

@onready var play_button: TextureButton = $MarginContainer/ButtonsContainer/PlayButton
@onready var exit_button: TextureButton = $MarginContainer/ButtonsContainer/ExitButton
@onready var button_sfx: AudioStreamPlayer = $ButtonSfx
@onready var hover_sfx: AudioStreamPlayer = _get_or_create_audio_player("HoverSfx", HOVER_SFX)

var _is_transitioning := false

func _ready() -> void:
	BgmManager.play_default()
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	play_button.mouse_entered.connect(_play_hover_sfx)
	exit_button.mouse_entered.connect(_play_hover_sfx)

func _on_play_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_set_buttons_disabled(true)
	_play_button_sfx()
	await get_tree().create_timer(0.12).timeout
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _on_exit_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_set_buttons_disabled(true)
	_play_button_sfx()
	await get_tree().create_timer(0.12).timeout
	get_tree().quit()

func _play_button_sfx() -> void:
	if button_sfx == null or button_sfx.stream == null:
		return
	button_sfx.stop()
	button_sfx.play()

func _play_hover_sfx() -> void:
	if hover_sfx == null or hover_sfx.stream == null:
		return
	hover_sfx.stop()
	hover_sfx.play()

func _get_or_create_audio_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var existing := get_node_or_null(player_name) as AudioStreamPlayer
	if existing != null:
		if existing.stream == null:
			existing.stream = stream
		return existing

	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player

func _set_buttons_disabled(disabled: bool) -> void:
	play_button.disabled = disabled
	exit_button.disabled = disabled
