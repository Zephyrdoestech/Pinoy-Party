# scenes/minigames/BaseMinigame.gd
class_name BaseMinigame
extends Node2D

## Player indices participating (set externally before start_game(), or read here)
var participating_players: Array[int] = []

# ---------------------------------------------------------------------------
# Shared pre-round intro: optional announcement (e.g. "Player 2 is IT!"),
# then a dimmed-background 3-2-1 countdown, before gameplay is allowed.
# Built dynamically at runtime so existing minigame scenes don't need any
# new nodes added by hand — applies uniformly to every minigame.
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


## Override in each minigame — called by SceneLoader after instancing
func start_game(players: Array[int]) -> void:
	participating_players = players


## Call from a subclass's start_game(), AFTER any setup that determines the
## announcement text (e.g. picking who is "IT") or world layout, and BEFORE
## any gameplay should be possible. `announcement_text` is optional — pass
## "" to skip straight to the countdown.
func run_intro(announcement_text: String = "") -> void:
	gameplay_locked = true
	_build_intro_overlay()

	if announcement_text != "":
		_intro_label.text = announcement_text
		await get_tree().create_timer(ANNOUNCEMENT_DURATION).timeout

	var remaining := int(COUNTDOWN_DURATION)
	while remaining > 0:
		_intro_label.text = str(remaining)
		await get_tree().create_timer(1.0).timeout
		remaining -= 1

	if is_instance_valid(_intro_layer):
		_intro_layer.queue_free()

	gameplay_locked = false
	intro_finished.emit()


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


## Call this when the minigame is fully resolved.
## Emits through EventBus so State_TileEvent's await catches it.
func _finish(scores: Dictionary) -> void:
	EventBus.minigame_finished.emit(scores)
	await get_tree().create_timer(2.0).timeout
	SceneLoader.return_to_board()
