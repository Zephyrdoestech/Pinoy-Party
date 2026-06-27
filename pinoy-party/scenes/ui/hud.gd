# scenes/ui/hud.gd
extends Control

var turn_label: Label

func _ready() -> void:
	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.position = Vector2(20, 20)
	add_child(turn_label)

	EventBus.turn_started.connect(_on_turn_started)

func _on_turn_started(player_index: int) -> void:
	var player_data: Dictionary = GameManager.players[player_index]
	turn_label.text = "%s's Turn — Press SPACE or click Roll" % player_data["name"]
	turn_label.modulate = player_data["color"]
