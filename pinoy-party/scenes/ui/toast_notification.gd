extends Control

## Slide-down toast for "needs a roll of X to win" messages.
## Built entirely at runtime - same pattern as hud.gd / score_board.gd.
## Root node of ToastNotification.tscn must be a Control.

const VISIBLE_DURATION_SEC := 2.0
const SLIDE_DURATION_SEC := 0.3
const HIDDEN_Y := -80.0
const SHOWN_Y := 20.0

var _panel: PanelContainer
var _label: Label
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position.y = HIDDEN_Y
	add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_label)

	EventBus.roll_exceeded.connect(_on_roll_exceeded)


func _on_roll_exceeded(player_index: int, tiles_needed: int) -> void:
	var player_name: String = GameManager.players[player_index]["name"]
	_label.text = "%s needs a roll of %d to win!" % [player_name, tiles_needed]
	_show_toast()


func _show_toast() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "position:y", SHOWN_Y, SLIDE_DURATION_SEC)
	_tween.tween_interval(VISIBLE_DURATION_SEC)
	_tween.tween_property(_panel, "position:y", HIDDEN_Y, SLIDE_DURATION_SEC)
