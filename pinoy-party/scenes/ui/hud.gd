# scenes/ui/hud.gd
extends Control

var turn_label: Label

func _ready() -> void:
	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	turn_label.offset_left = -520.0
	turn_label.offset_top = -72.0
	turn_label.offset_right = -24.0
	turn_label.offset_bottom = -24.0
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_label.clip_text = true
	add_child(turn_label)

	EventBus.turn_started.connect(_on_turn_started)

func _on_turn_started(player_index: int) -> void:
	var player_data: Dictionary = GameManager.players[player_index]
	turn_label.text = "%s's Turn — Press SPACE or click Roll" % player_data["name"]
	turn_label.modulate = player_data["color"]
