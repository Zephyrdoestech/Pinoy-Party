# scenes/ui/game_over_screen.gd
extends Control

var headline: Label
var score_rows: Array = []  # [{score: Label}] per player, indexed by player_index
var restart_button: Button
const CUSTOM_FONT_PATH := "res://assets/fonts/GrapeSoda.ttf"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	# Block clicks from reaching anything underneath while shown.
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	var custom_font = load(CUSTOM_FONT_PATH)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.85)
	add_child(dim)

	headline = Label.new()
	headline.add_theme_font_size_override("font_size", 56)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.set_anchors_preset(Control.PRESET_TOP_WIDE)
	headline.position.y = 100.0 
	if custom_font:
		headline.add_theme_font_override("font", custom_font)
	add_child(headline)

	restart_button = Button.new()
	restart_button.text = "Play Again"
	restart_button.custom_minimum_size = Vector2(160, 48)
	restart_button.pressed.connect(_on_restart_pressed)
	if custom_font:
		restart_button.add_theme_font_override("font", custom_font)
		restart_button.add_theme_font_size_override("font_size", 20)
	add_child(restart_button)
	restart_button.set_anchors_preset(Control.PRESET_CENTER)
	restart_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	restart_button.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	restart_button.position.y += 120.0
	EventBus.game_over.connect(_on_game_over)

func _on_game_over(winner_index: int) -> void:
	var winner_data: Dictionary = GameManager.players[winner_index]
	headline.text = "%s Wins!" % winner_data["name"]
	headline.modulate = winner_data["color"]

	visible = true

func _on_restart_pressed() -> void:
	visible = false
	if NetworkManager.is_host:
		NetworkManager.request_restart()
	else:
		NetworkManager.request_restart.rpc_id(1)
