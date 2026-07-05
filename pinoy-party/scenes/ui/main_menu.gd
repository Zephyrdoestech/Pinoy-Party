extends Control

const LOBBY_SCENE_PATH := "res://scenes/ui/LobbyScreen.tscn"

@onready var play_button: TextureButton = $MarginContainer/ButtonsContainer/PlayButton
@onready var exit_button: TextureButton = $MarginContainer/ButtonsContainer/ExitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _on_exit_pressed() -> void:
	get_tree().quit()
