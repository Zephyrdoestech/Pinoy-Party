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

	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(panel)

	headline = Label.new()
	headline.add_theme_font_size_override("font_size", 56)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if custom_font:
		headline.add_theme_font_override("font", custom_font)
	panel.add_child(headline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	panel.add_child(spacer)

	for i in Constants.MAX_PLAYERS:
		var score_label := Label.new()
		score_label.add_theme_font_size_override("font_size", 24)
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if custom_font:
			score_label.add_theme_font_override("font", custom_font)
		panel.add_child(score_label)
		score_rows.append(score_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 24)
	panel.add_child(spacer2)

	restart_button = Button.new()
	restart_button.text = "Play Again"
	restart_button.custom_minimum_size = Vector2(160, 48)
	restart_button.pressed.connect(_on_restart_pressed)
	if custom_font:
		restart_button.add_theme_font_override("font", custom_font)
		restart_button.add_theme_font_size_override("font_size", 20)
	add_child(restart_button)
	
	restart_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	restart_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	restart_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	restart_button.offset_left = -80
	restart_button.offset_right = 80
	restart_button.offset_bottom = -60
	restart_button.offset_top = -108
	
	EventBus.game_over.connect(_on_game_over)

func _on_game_over(winner_index: int) -> void:
	var winner_data: Dictionary = GameManager.players[winner_index]
	headline.text = "%s Wins!" % winner_data["name"]
	headline.modulate = winner_data["color"]

	for i in Constants.MAX_PLAYERS:
		var label: Label = score_rows[i]
		if i < GameManager.active_player_count:
			var p: Dictionary = GameManager.players[i]
			label.text = "%s: %d" % [p["name"], p["score"]]
			label.modulate = p["color"]
			label.add_theme_font_size_override("font_size", 32 if i == winner_index else 24)
			label.show()
		else:
			label.hide()
	visible = true

func _on_restart_pressed() -> void:
	visible = false
	if NetworkManager.is_host:
		NetworkManager.request_restart()
	else:
		NetworkManager.request_restart.rpc_id(1)
