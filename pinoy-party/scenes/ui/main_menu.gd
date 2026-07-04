extends Control

const LOBBY_SCENE_PATH := "res://scenes/ui/LobbyScreen.tscn"

var play_button: BaseButton
var exit_button: BaseButton

func _ready() -> void:
	play_button = find_child("PlayButton", true, false) as BaseButton
	exit_button = find_child("ExitButton", true, false) as BaseButton

	if play_button == null or exit_button == null:
		_build_fallback_ui()
	else:
		_center_buttons_vertically()
		_add_button_gap()

	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

func _center_buttons_vertically() -> void:
	var container := play_button.get_parent() as Control
	if container == null:
		return

	var height := container.size.y
	if height <= 0.0:
		height = container.custom_minimum_size.y
	if height <= 0.0:
		height = play_button.size.y + exit_button.size.y + 18.0

	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.offset_top = -height * 0.5
	container.offset_bottom = height * 0.5

func _add_button_gap() -> void:
	var container := play_button.get_parent()
	if container is BoxContainer:
		(container as BoxContainer).add_theme_constant_override("separation", 18)

func _build_fallback_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_constant_override("separation", 18)
	center.add_child(panel)

	var title := Label.new()
	title.text = "Pinoy Party"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	panel.add_child(title)

	play_button = Button.new()
	play_button.name = "PlayButton"
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(200, 50)
	panel.add_child(play_button)

	exit_button = Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "Exit"
	exit_button.custom_minimum_size = Vector2(200, 50)
	panel.add_child(exit_button)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _on_exit_pressed() -> void:
	get_tree().quit()
