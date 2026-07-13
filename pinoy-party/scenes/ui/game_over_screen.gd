# scenes/ui/game_over_screen.gd
extends Control

var headline: Label
var score_rows: Array = []  # [{score: Label}] per player, indexed by player_index
var restart_button: Button
const CUSTOM_FONT_PATH := "res://assets/fonts/GrapeSoda.ttf"
const WINNING_CONTAINER := preload("res://assets/screens/winning_container.png")
const LOSING_CONTAINER := preload("res://assets/screens/losing_container.png")
const VICTORY_SFX := preload("res://assets/sfx/board/victory_sfx.mp3")
const GAME_OVER_SFX := preload("res://assets/sfx/board/game_over_sfx.mp3")
const ROW_SIZE := Vector2(460, 72)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	# Block clicks from reaching anything underneath while shown.
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	var custom_font = load(CUSTOM_FONT_PATH)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	add_child(dim)

	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 460)
	panel.offset_left = -260.0
	panel.offset_top = -260.0
	panel.offset_right = 260.0
	panel.offset_bottom = 200.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 10)
	add_child(panel)

	var title := Label.new()
	title.text = "Game Over"
	title.add_theme_font_size_override("font_size", 86)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.22))
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.03))
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if custom_font:
		title.add_theme_font_override("font", custom_font)
	panel.add_child(title)

	headline = Label.new()
	headline.add_theme_font_size_override("font_size", 72)
	headline.add_theme_color_override("font_outline_color", Color(0.18, 0.07, 0.04))
	headline.add_theme_constant_override("outline_size", 6)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if custom_font:
		headline.add_theme_font_override("font", custom_font)
	panel.add_child(headline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	panel.add_child(spacer)

	for i in GameManager.active_player_count:
		var row_bg := TextureRect.new()
		row_bg.custom_minimum_size = ROW_SIZE
		row_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row_bg.stretch_mode = TextureRect.STRETCH_SCALE
		panel.add_child(row_bg)

		var score_label := Label.new()
		score_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		score_label.offset_left = 28.0
		score_label.offset_right = -28.0
		score_label.add_theme_font_size_override("font_size", 34)
		score_label.add_theme_color_override("font_color", Color(0.13, 0.08, 0.05))
		score_label.add_theme_color_override("font_outline_color", Color(1, 0.94, 0.75))
		score_label.add_theme_constant_override("outline_size", 3)
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if custom_font:
			score_label.add_theme_font_override("font", custom_font)
		row_bg.add_child(score_label)
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
	_play_game_over_sfx(winner_index)
	var winner_data: Dictionary = GameManager.players[winner_index]
	headline.text = "%s Won!" % winner_data["name"]
	headline.modulate = winner_data["color"]

	# score_rows was built for active_player_count, so index directly with no
	# hide/show branching needed — every row corresponds to a real player.
	for i in GameManager.active_player_count:
		var label: Label = score_rows[i]
		var p: Dictionary = GameManager.players[i]
		var row_bg := label.get_parent() as TextureRect
		if row_bg:
			row_bg.texture = WINNING_CONTAINER if i == winner_index else LOSING_CONTAINER
		label.text = "%s  -  %d Points" % [p["name"], p["score"]]
		label.modulate = p["color"]
		label.add_theme_font_size_override("font_size", 42 if i == winner_index else 34)
	visible = true

func _on_restart_pressed() -> void:
	visible = false
	if NetworkManager.is_host:
		NetworkManager.request_restart()
	else:
		NetworkManager.request_restart.rpc_id(1)

func _play_game_over_sfx(winner_index: int) -> void:
	var my_player_index := NetworkManager.get_my_player_index()
	var is_local_or_winner := my_player_index == -1 or my_player_index == winner_index
	_play_sfx("GameOverResultSfx", VICTORY_SFX if is_local_or_winner else GAME_OVER_SFX)

func _play_sfx(player_name: String, stream: AudioStream) -> void:
	var player := _get_or_create_sfx_player(player_name, stream)
	if player == null or player.stream == null:
		return
	player.stop()
	player.play()

func _get_or_create_sfx_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var existing := get_node_or_null(player_name) as AudioStreamPlayer
	if existing != null:
		if existing.stream == null:
			existing.stream = stream
		return existing

	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player
