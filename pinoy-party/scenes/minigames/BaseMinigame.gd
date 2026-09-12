# scenes/minigames/BaseMinigame.gd
class_name BaseMinigame
extends Node2D

## Player indices participating (set externally before start_game(), or read here)
var participating_players: Array[int] = []

const JUMP_SFX := preload("res://assets/sfx/minigame/jump_sfx.mp3")
const MINIGAME_FINISH_SFX := preload("res://assets/sfx/minigame/minigame_finish_sfx.mp3")
const APPLAUSE_SFX := preload("res://assets/sfx/minigame/applause_sfx.mp3")
const COUNTDOWN_SFX := preload("res://assets/sfx/board/3_seconds_countdown_sfx.mp3")
const UI_FONT := preload("res://assets/fonts/GrapeSoda.ttf")
const WINNING_SCORE_CONTAINER := preload("res://assets/minigame_assets/winning_score_container.png")
const SECOND_PLACE_SCORE_CONTAINER := preload("res://assets/minigame_assets/2nd_place_score_container.png")
const THIRD_PLACE_SCORE_CONTAINER := preload("res://assets/minigame_assets/3rd_place_score_container.png")
const LAST_PLACE_SCORE_CONTAINER := preload("res://assets/minigame_assets/last_place_score_container.png")
const MINIGAME_GAMEOVER_BG := preload("res://assets/game over assets/Minigame_gameover_bg.png")
const RESULT_ROW_SIZE := Vector2(512, 128)
const RESULT_MARGIN_X := 36.0
const RESULT_TOP_SPACE := 112.0
const RESULT_BOTTOM_SPACE := 24.0
const RESULT_COLUMN_GAP := 12.0
const GLOBAL_PLAYER_PORTRAITS := {
	0: {
		"win": preload("res://assets/game over assets/charac1_happy.png"),
		"sad": preload("res://assets/game over assets/charac1_sad.png")
	},
	1: {
		"win": preload("res://assets/game over assets/charac2_happy.png"),
		"sad": preload("res://assets/game over assets/charac2_sad.png")
	},
	2: {
		"win": preload("res://assets/game over assets/charac3_happy.png"),
		"sad": preload("res://assets/game over assets/charac3_sad.png")
	},
	3: {
		"win": preload("res://assets/game over assets/charac4_happy.png"),
		"sad": preload("res://assets/game over assets/charac4_sad.png")
	}
}

# ---------------------------------------------------------------------------
# Shared pre-round intro: optional announcement (e.g. "Player 2 is IT!"),
# then a dimmed-background 3-2-1 countdown, before gameplay is allowed.
# Built dynamically at runtime so existing minigame scenes don't need any
# new nodes added by hand - applies uniformly to every minigame.
# ---------------------------------------------------------------------------
const INTRO_DIM_ALPHA := 0.85       # background is barely visible during intro
const ANNOUNCEMENT_DURATION := 2.0  # seconds
const COUNTDOWN_DURATION := 3.0     # seconds (3, 2, 1)


## Subclasses MUST check this at the top of _process() and bail out early
## (`if gameplay_locked: return`) until run_intro() finishes. This is what
## actually prevents movement/timers/tagging from running during the intro.
var gameplay_locked := true

signal intro_finished

var _intro_layer: CanvasLayer
var _intro_dim: ColorRect
var _intro_label: Label


## Override in each minigame - called by SceneLoader after instancing
func start_game(players: Array[int]) -> void:
	participating_players = players


# ---------------------------------------------------------------------------
# Shared placement scoring for "elimination" minigames (LuksongBaka,
# SackRace) - anywhere players are progressively knocked out and the result
# is a 1st/2nd/3rd placement.
#
# `groups` must be ordered BEST placement first, where each element is an
# Array[int] of player indices who tied for that placement block (size 1 =
# no tie). A tied group is awarded the point value of the WORST individual
# rank their group would have spanned had they not tied - e.g. two players
# tied for what would have been 2nd/3rd both get 3rd's value. Any rank
# beyond 3rd scores 0. See DEVLOG.md for the worked examples this matches.
# ---------------------------------------------------------------------------
const PLACEMENT_POINTS := {1: 3, 2: 2, 3: 1}

static func compute_placement_scores(groups: Array) -> Dictionary:
	var scores: Dictionary = {}
	var rank_cursor := 1
	for group in groups:
		var worst_rank: int = rank_cursor + group.size() - 1
		var reward := 0
		if rank_cursor <= 3:
			reward = PLACEMENT_POINTS.get(min(worst_rank, 3), 0)
		for idx in group:
			scores[idx] = reward
		rank_cursor += group.size()
	return scores


## Call from a subclass's start_game(), AFTER any setup that determines the
## announcement text (e.g. picking who is "IT") or world layout, and BEFORE
## any gameplay should be possible. `announcement_text` is optional - pass
## "" to skip straight to the countdown.
func run_intro(announcement_text: String = "") -> void:
	gameplay_locked = true
	set_process_unhandled_input(false) # belt-and-suspenders: no inputs reach any minigame during the intro
	_build_intro_overlay()

	if announcement_text != "":
		_intro_label.text = announcement_text
		await get_tree().create_timer(ANNOUNCEMENT_DURATION).timeout

	var remaining := int(COUNTDOWN_DURATION)
	while remaining > 0:
		_intro_label.text = str(remaining)
		play_countdown_sfx()
		await get_tree().create_timer(1.0).timeout
		remaining -= 1

	if is_instance_valid(_intro_layer):
		_intro_layer.queue_free()

	gameplay_locked = false
	set_process_unhandled_input(true)
	intro_finished.emit()

func run_results(scores: Dictionary) -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var viewport_size := get_viewport_rect().size

	var victory_bg := TextureRect.new()
	victory_bg.texture = MINIGAME_GAMEOVER_BG
	victory_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	victory_bg.stretch_mode = TextureRect.STRETCH_SCALE
	canvas.add_child(victory_bg)

	var winner_idx := _get_winner_index(scores)

	var top_label := Label.new()
	top_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_label.offset_top = 18.0
	top_label.offset_bottom = RESULT_TOP_SPACE
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_label.add_theme_font_override("font", UI_FONT)
	top_label.add_theme_font_size_override("font_size", _scaled_font(64, viewport_size.x / 1280.0, 42, 64))
	top_label.add_theme_color_override("font_color", Color.WHITE)
	top_label.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.05))
	top_label.add_theme_constant_override("outline_size", 5)
	top_label.text = "%s Won!" % _get_player_name(winner_idx) if winner_idx != -1 else "It's a Tie!"
	canvas.add_child(top_label)
	play_applause_sfx()

	var content := HBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = RESULT_MARGIN_X
	content.offset_top = RESULT_TOP_SPACE
	content.offset_right = -RESULT_MARGIN_X
	content.offset_bottom = -RESULT_BOTTOM_SPACE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", RESULT_COLUMN_GAP)
	canvas.add_child(content)

	var result_players := _get_result_player_indices(scores)
	var layout := _get_result_layout(viewport_size, result_players.size())
	var place_index := -1
	var last_points = null
	for row_index in result_players.size():
		var idx: int = result_players[row_index]
		var points: int = scores.get(idx, 0)
		if last_points == null or points != last_points:
			place_index += 1
			last_points = points
		var player_column := VBoxContainer.new()
		player_column.alignment = BoxContainer.ALIGNMENT_END
		player_column.custom_minimum_size = Vector2(layout["column_width"], layout["content_height"])
		player_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		player_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		player_column.add_theme_constant_override("separation", layout["column_gap"])
		content.add_child(player_column)

		var portrait := TextureRect.new()
		var textures: Dictionary = GLOBAL_PLAYER_PORTRAITS.get(idx, {})
		portrait.texture = textures.get("win") if winner_idx != -1 and idx == winner_idx else textures.get("sad")
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.custom_minimum_size = Vector2(layout["column_width"], layout["portrait_height"])
		player_column.add_child(portrait)

		var row_bg := TextureRect.new()
		row_bg.texture = _get_result_row_texture(place_index)
		row_bg.custom_minimum_size = layout["row_size"]
		row_bg.size = layout["row_size"]
		row_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row_bg.stretch_mode = TextureRect.STRETCH_SCALE
		player_column.add_child(row_bg)

		var score_label := _make_result_label(_scaled_font(38 if place_index == 0 else 34, layout["scale"], 20, 38))
		score_label.text = "%s  %s" % [_get_player_name(idx), _format_points(points)]
		score_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		score_label.offset_left = 24.0 * layout["scale"]
		score_label.offset_right = -24.0 * layout["scale"]
		row_bg.add_child(score_label)

	# Let the screen linger as a single complete victory screen, then clean up
	await get_tree().create_timer(5.0).timeout
	canvas.queue_free()

func _make_result_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.13, 0.08, 0.05))
	label.add_theme_color_override("font_outline_color", Color(1, 0.94, 0.75))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	return label

func _get_result_layout(viewport_size: Vector2, player_count: int) -> Dictionary:
	var safe_count: int = max(player_count, 1)
	var available_width: float = max(320.0, viewport_size.x - RESULT_MARGIN_X * 2.0 - RESULT_COLUMN_GAP * (safe_count - 1))
	var column_width: float = min(RESULT_ROW_SIZE.x, floor(available_width / safe_count))
	var scale: float = clamp(column_width / RESULT_ROW_SIZE.x, 0.46, 1.0)
	var row_size := RESULT_ROW_SIZE * scale
	var content_height: float = max(220.0, viewport_size.y - RESULT_TOP_SPACE - RESULT_BOTTOM_SPACE)
	var portrait_height: float = max(120.0, content_height - row_size.y - 8.0)
	return {
		"column_width": column_width,
		"content_height": content_height,
		"portrait_height": portrait_height,
		"row_size": row_size,
		"scale": scale,
		"column_gap": -6.0 * scale,
	}

func _scaled_font(base_size: int, scale: float, min_size: int, max_size: int) -> int:
	return int(clamp(round(float(base_size) * scale), min_size, max_size))

func _get_result_player_indices(scores: Dictionary) -> Array:
	var result_players: Array = participating_players.duplicate()
	for idx in scores.keys():
		if not result_players.has(idx):
			result_players.append(idx)
	result_players.sort_custom(func(a, b): return scores.get(a, 0) > scores.get(b, 0))
	return result_players

func _get_result_row_texture(row_index: int) -> Texture2D:
	match row_index:
		0:
			return WINNING_SCORE_CONTAINER
		1:
			return SECOND_PLACE_SCORE_CONTAINER
		2:
			return THIRD_PLACE_SCORE_CONTAINER
		_:
			return LAST_PLACE_SCORE_CONTAINER

func _get_player_name(player_idx: int) -> String:
	if player_idx >= 0 and player_idx < GameManager.players.size():
		return GameManager.players[player_idx].get("name", "Player %d" % (player_idx + 1))
	return "Player %d" % (player_idx + 1)

func _point_word(points: int) -> String:
	return "Point" if abs(points) == 1 else "Points"

func _format_points(points: int) -> String:
	if points == 0:
		return "No Points"
	return "+%d %s" % [points, _point_word(points)]

func _get_winner_index(scores: Dictionary) -> int:
	var best_idx := -1
	var best_score := -1
	var tied := false
	for idx in scores.keys():
		if scores[idx] > best_score:
			best_score = scores[idx]
			best_idx = idx
			tied = false
		elif scores[idx] == best_score:
			tied = true
	return -1 if tied else int(best_idx)

func _build_intro_overlay() -> void:
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 100
	add_child(_intro_layer)

	_intro_dim = ColorRect.new()
	_intro_dim.color = Color(0, 0, 0, INTRO_DIM_ALPHA)
	_intro_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(_intro_dim)

	_intro_label = Label.new()
	_intro_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_label.add_theme_font_size_override("font_size", 48)
	_intro_layer.add_child(_intro_label)

func play_jump_sfx() -> void:
	_play_minigame_sfx("JumpSfx", JUMP_SFX)

func play_minigame_finish_sfx() -> void:
	_play_minigame_sfx("MinigameFinishSfx", MINIGAME_FINISH_SFX)

func play_applause_sfx() -> void:
	_play_minigame_sfx("ApplauseSfx", APPLAUSE_SFX)

func play_countdown_sfx() -> void:
	_play_minigame_sfx("CountdownSfx", COUNTDOWN_SFX)

func _play_minigame_sfx(player_name: String, stream: AudioStream) -> void:
	var player := _get_or_create_minigame_sfx_player(player_name, stream)
	if player == null or player.stream == null:
		return
	player.stop()
	player.play()

func _get_or_create_minigame_sfx_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
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


## Call this when the minigame is fully resolved.
## Emits through EventBus so GameManager's autoload handler catches it.
## IMPORTANT: run_results() is awaited FIRST so the 5-second results screen
## completes before scores are applied and game-over is checked.  Emitting
## before the await caused the game-over overlay to appear on top of the
## still-visible results screen.
func _finish(scores: Dictionary) -> void:
	play_minigame_finish_sfx()
	await run_results(scores)
	EventBus.minigame_finished.emit(scores)
	SceneLoader.return_to_board()
	
