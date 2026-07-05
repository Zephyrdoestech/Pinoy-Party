# scenes/ui/hud.gd
extends Control

const TURN_LOG_BG := preload("res://assets/board_assets/board-turn_logs_bg.png")
const HUD_FONT := preload("res://assets/fonts/GrapeSoda.ttf")

var turn_bg: TextureRect
var turn_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	turn_bg = TextureRect.new()
	turn_bg.texture = TURN_LOG_BG
	turn_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	turn_bg.offset_left = -520.0
	turn_bg.offset_top = -72.0
	turn_bg.offset_right = -8.0
	turn_bg.offset_bottom = -8.0
	turn_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	turn_bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(turn_bg)

	turn_label = Label.new()
	turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_label.add_theme_font_override("font", HUD_FONT)
	turn_label.add_theme_font_size_override("font_size", 28)
	turn_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	turn_label.offset_left = -492.0
	turn_label.offset_top = -62.0
	turn_label.offset_right = -32.0
	turn_label.offset_bottom = -18.0
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_label.clip_text = true
	add_child(turn_label)

	EventBus.turn_started.connect(_on_turn_started)

func _on_turn_started(player_index: int) -> void:
	var player_data: Dictionary = GameManager.players[player_index]
	turn_label.text = "%s's Turn - Press SPACE or click Roll" % player_data["name"]
	turn_label.modulate = player_data["color"]
