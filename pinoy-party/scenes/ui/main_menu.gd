extends Control

## Simple main menu: Play + Exit. Built entirely at runtime, same
## "no scene edits needed" approach as hud.gd / score_board.gd / game_over_screen.gd.
## Root node of MainMenu.tscn must be a Control (matches this script's `extends`).

const LOBBY_SCENE_PATH := "res://scenes/ui/LobbyScreen.tscn"

func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centered container — explicitly sized rather than left to PRESET_CENTER's
	# default, same gotcha noted in TriviaController: an unconstrained container
	# centers its own origin, not its content, which can look off-center.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_constant_override("separation", 16)
	center.add_child(panel)

	var title := Label.new()
	title.text = "Pinoy Party"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	panel.add_child(title)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(200, 50)
	panel.add_child(play_button)

	var exit_button := Button.new()
	exit_button.text = "Exit"
	exit_button.custom_minimum_size = Vector2(200, 50)
	panel.add_child(exit_button)

	# Connect explicitly in code — do NOT rely on editor-side signal wiring.
	# See lobby_screen.gd's "editor-wired signals silently missing" gotcha in
	# DEVLOG.md: a disconnected signal produces zero console output and looks
	# identical to a broken handler.
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


func _on_exit_pressed() -> void:
	get_tree().quit()
