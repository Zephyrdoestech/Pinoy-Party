# scenes/ui/game_over_screen.gd
extends Control

var headline: Label
var score_rows: Array = []  # [{score: Label}] per player, indexed by player_index
var restart_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	# Block clicks from reaching anything underneath while shown.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.85)
	add_child(dim)

	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(panel)

	headline = Label.new()
	headline.add_theme_font_size_override("font_size", 40)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(headline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	panel.add_child(spacer)

	for i in Constants.MAX_PLAYERS:
		var score_label := Label.new()
		score_label.add_theme_font_size_override("font_size", 24)
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(score_label)
		score_rows.append(score_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 24)
	panel.add_child(spacer2)

	restart_button = Button.new()
	restart_button.text = "Play Again"
	restart_button.custom_minimum_size = Vector2(160, 48)
	restart_button.pressed.connect(_on_restart_pressed)
	panel.add_child(restart_button)

	EventBus.game_over.connect(_on_game_over)

func _on_game_over(winner_index: int) -> void:
	var winner_data: Dictionary = GameManager.players[winner_index]
	headline.text = "%s Wins!" % winner_data["name"]
	headline.modulate = winner_data["color"]

	for i in Constants.MAX_PLAYERS:
		var p: Dictionary = GameManager.players[i]
		var label: Label = score_rows[i]
		label.text = "%s: %d" % [p["name"], p["score"]]
		label.modulate = p["color"]
		# Make the winner's row stand out among the rest.
		label.add_theme_font_size_override("font_size", 32 if i == winner_index else 24)

	visible = true

func _on_restart_pressed() -> void:
	visible = false
	GameManager.reset_for_new_game()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
