# scenes/ui/score_board.gd
extends Control

# One row per player: a "▶" marker (shown only on the current player) and a
# "Name: score" label, colored to match that player's token color.
var rows: Array = []  # [{marker: Label, score: Label}]

func _ready() -> void:
	for i in Constants.MAX_PLAYERS:
		var row := HBoxContainer.new()
		row.position = Vector2(0, i * 28)

		var marker := Label.new()
		marker.custom_minimum_size = Vector2(20, 0)
		marker.text = ""
		row.add_child(marker)

		var score_label := Label.new()
		row.add_child(score_label)

		add_child(row)
		rows.append({"marker": marker, "score": score_label})

	EventBus.score_changed.connect(_on_score_changed)
	EventBus.turn_started.connect(_on_turn_started)
	_refresh_all()

func _refresh_all() -> void:
	for i in Constants.MAX_PLAYERS:
		_update_score_text(i)

func _update_score_text(player_index: int) -> void:
	var p: Dictionary = GameManager.players[player_index]
	var score_label: Label = rows[player_index]["score"]
	score_label.text = "%s: %d" % [p["name"], p["score"]]
	score_label.modulate = p["color"]

func _on_score_changed(player_index: int, _new_score: int) -> void:
	_update_score_text(player_index)

func _on_turn_started(current_player_index: int) -> void:
	for i in Constants.MAX_PLAYERS:
		var marker: Label = rows[i]["marker"]
		marker.text = "▶" if i == current_player_index else ""
