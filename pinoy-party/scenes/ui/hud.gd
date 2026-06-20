# scenes/ui/hud.gd
extends Control

@onready var turn_label: Label = $TurnLabel

func _ready() -> void:
	EventBus.turn_started.connect(_on_turn_started)

func _on_turn_started(player_index: int) -> void:
	var player_data: Dictionary = GameManager.players[player_index]
	turn_label.text = "%s's Turn — Press SPACE or click Roll" % player_data["name"]
	turn_label.modulate = player_data["color"]
