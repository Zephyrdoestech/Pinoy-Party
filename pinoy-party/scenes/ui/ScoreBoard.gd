# scenes/ui/score_board.gd
extends Control

# One row per player: a "▶" marker (shown only on the current player) and a
# "Name: score" label, colored to match that player's token color.
var rows: Array = []  # [{marker: Label, score: Label}]

func _ready() -> void:
	var container = $RowsContainer
	
	# Loop through the actual visual rows you built in the editor
	for row_rect in container.get_children():
		var marker = row_rect.get_node_or_null("HBox/Marker")
		var score_label = row_rect.get_node_or_null("HBox/Score")
		
		if marker and score_label:
			rows.append({"marker": marker, "score": score_label})

	# Hide rows that have no player in this match.
	# The scene always has MAX_PLAYERS (4) rows; in a 2-player game
	# rows[2] and rows[3] would show as empty blanks without this.
	var active := GameManager.active_player_count
	for i in rows.size():
		rows[i]["marker"].get_parent().get_parent().visible = i < active
			
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.turn_started.connect(_on_turn_started)
	
	_refresh_all()

func _refresh_all() -> void:
	var display_count = min(GameManager.players.size(), rows.size())
	for i in display_count:
		_update_score_text(i)

func _update_score_text(player_index: int) -> void:
	if player_index >= GameManager.players.size():
		return
	var p: Dictionary = GameManager.players[player_index]
	var score_label: Label = rows[player_index]["score"]
	score_label.text = "%s: %d" % [p["name"], p["score"]]
	score_label.modulate = p["color"]

func _on_score_changed(player_index: int, _new_score: int) -> void:
	_update_score_text(player_index)

func _on_turn_started(current_player_index: int) -> void:
	var display_count = min(GameManager.players.size(), rows.size())
	for i in display_count:
		var marker: Label = rows[i]["marker"]
		marker.text = "▶" if i == current_player_index else ""
