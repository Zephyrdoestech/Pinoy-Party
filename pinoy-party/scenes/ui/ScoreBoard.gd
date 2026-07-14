# scenes/ui/score_board.gd
extends Control

const BOARD_SIZE := Vector2(384, 256)
const BOARD_MARGIN := Vector2(20, 20)
const ROW_START := Vector2(78, 48)
const ROW_GAP := 8.0
const ROW_SIZE := Vector2(228, 42)
const BG_TEXTURE := preload("res://assets/board_assets/LeaderBoard/leaderboard_bg.png")

# One row per player: a "▶" marker (shown only on the current player) and a
# "Name: score" label, colored to match that player's token color.
var rows: Array = []  # [{marker: Label, score: Label}]

func _ready() -> void:
	_setup_board_frame()
	var container = $RowsContainer
	container.position = ROW_START
	container.add_theme_constant_override("separation", ROW_GAP)
	
	# Loop through the actual visual rows you built in the editor
	for row_rect in container.get_children():
		_format_row(row_rect)
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

func _setup_board_frame() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(BOARD_SIZE.x + BOARD_MARGIN.x)
	offset_top = BOARD_MARGIN.y
	offset_right = -BOARD_MARGIN.x
	offset_bottom = BOARD_MARGIN.y + BOARD_SIZE.y
	custom_minimum_size = BOARD_SIZE
	size = BOARD_SIZE

	var bg := get_node_or_null("LeaderboardBg") as TextureRect
	if bg == null:
		bg = TextureRect.new()
		bg.name = "LeaderboardBg"
		add_child(bg)
		move_child(bg, 0)
	bg.texture = BG_TEXTURE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _format_row(row_rect: Node) -> void:
	if row_rect is Control:
		row_rect.custom_minimum_size = ROW_SIZE
		row_rect.size = ROW_SIZE
		row_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if row_rect is TextureRect:
		row_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row_rect.stretch_mode = TextureRect.STRETCH_KEEP

	var hbox := row_rect.get_node_or_null("HBox") as HBoxContainer
	if hbox:
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.offset_left = 44.0
		hbox.offset_top = 4.0
		hbox.offset_right = -12.0
		hbox.offset_bottom = -4.0
		hbox.add_theme_constant_override("separation", 6)

	var marker := row_rect.get_node_or_null("HBox/Marker") as Label
	if marker:
		marker.custom_minimum_size = Vector2(18, 34)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))

	var score_label := row_rect.get_node_or_null("HBox/Score") as Label
	if score_label:
		score_label.custom_minimum_size = Vector2(150, 34)
		score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_label.clip_text = true

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
		marker.text = "    ▶" if i == current_player_index else ""
