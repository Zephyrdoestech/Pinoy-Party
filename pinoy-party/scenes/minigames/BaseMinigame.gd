# scenes/minigames/BaseMinigame.gd
class_name BaseMinigame
extends Node2D

## Player indices participating (set externally before start_game(), or read here)
var participating_players: Array[int] = []

const JUMP_SFX := preload("res://assets/sfx/minigame/jump_sfx.mp3")
const MINIGAME_FINISH_SFX := preload("res://assets/sfx/minigame/minigame_finish_sfx.mp3")
const APPLAUSE_SFX := preload("res://assets/sfx/minigame/applause_sfx.mp3")
const COUNTDOWN_SFX := preload("res://assets/sfx/board/3_seconds_countdown_sfx.mp3")

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

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dim)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", 48)
	canvas.add_child(label)

	# Phase 1: winner announcement
	var winner_idx := _get_winner_index(scores)
	label.text = "Player %d Wins!" % (winner_idx + 1) if winner_idx != -1 else "It's a Tie!"
	play_applause_sfx()
	await get_tree().create_timer(2.0).timeout

	# Phase 2: points breakdown
	label.queue_free()
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	canvas.add_child(vbox)

	var header := Label.new()
	header.text = "Points Earned"
	header.add_theme_font_size_override("font_size", 36)
	vbox.add_child(header)

	for idx in scores.keys():
		var row := Label.new()
		row.text = "Player %d: +%d pts" % [idx + 1, scores[idx]]
		row.add_theme_font_size_override("font_size", 28)
		vbox.add_child(row)

	await get_tree().create_timer(2.0).timeout
	canvas.queue_free()


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
	return -1 if tied else best_idx

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
## Emits through EventBus so State_TileEvent's await catches it.
func _finish(scores: Dictionary) -> void:
	play_minigame_finish_sfx()
	EventBus.minigame_finished.emit(scores)
	await run_results(scores)
	SceneLoader.return_to_board()
	
