extends Control

const LOBBY_SCENE_PATH := "res://scenes/ui/LobbyScreen.tscn"

@onready var play_button: TextureButton = $MarginContainer/ButtonsContainer/PlayButton
@onready var exit_button: TextureButton = $MarginContainer/ButtonsContainer/ExitButton
@onready var button_sfx: AudioStreamPlayer = $ButtonSfx

var _is_transitioning := false

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

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

func _set_buttons_disabled(disabled: bool) -> void:
	play_button.disabled = disabled
	exit_button.disabled = disabled
