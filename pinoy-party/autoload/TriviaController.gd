# autoload/TriviaController.gd
extends CanvasLayer

const UI_FONT := preload("res://assets/fonts/GrapeSoda.ttf")
const TRIVIA_BG := preload("res://assets/board_assets/Trivia/trivia_bg.png")
const QUESTION_BG := preload("res://assets/board_assets/Trivia/trivia_questions_container_bg.png")
const TIMER_BG := preload("res://assets/board_assets/Trivia/timer_container.png")
const CORRECT_BG := preload("res://assets/board_assets/Trivia/correct_container.png")
const INCORRECT_BG := preload("res://assets/board_assets/Trivia/incorrect_container.png")
const ANSWER_BGS: Array[Texture2D] = [
	preload("res://assets/board_assets/Trivia/trivia_answer_container_1.png"),
	preload("res://assets/board_assets/Trivia/trivia_answer_container_2.png"),
	preload("res://assets/board_assets/Trivia/trivia_answer_container_3.png"),
	preload("res://assets/board_assets/Trivia/trivia_answer_container_4.png"),
]

const TEXT_COLOR := Color(0.12, 0.16, 0.24)
const HOVER_TEXT_COLOR := Color(0.30, 0.36, 0.48)
const DISABLED_TEXT_COLOR := Color(0.12, 0.16, 0.24, 0.55)
const PANEL_SIZE := Vector2(768, 384)
const QUESTION_SIZE := Vector2(702, 102)
const ANSWER_SIZE := Vector2(708, 48)
const STATUS_SIZE := Vector2(192, 96)


var _submitted_answers: Dictionary = {}  # player_idx -> option_index
var _overlay: Control
var _status_texture: TextureRect
var _timer_label: Label
var _score_label: Label  # shows answering player's current total score
var _option_buttons: Array[TextureButton] = []
var _option_labels: Array[Label] = []
var _current_selection: int = 0
var _selected_option: int = -1
var _has_submitted: bool = false
var _answering_player_idx: int = -1
var _timer_remaining: float = 0.0
var _timer_active: bool = false

func _ready() -> void:
	EventBus.trivia_started.connect(_on_trivia_started)
	layer = 100  # draw above everything
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	if not _timer_active:
		return

	_timer_remaining = maxf(0.0, _timer_remaining - delta)
	_update_timer_label()
	if _timer_remaining <= 0.0:
		_timer_active = false

func _on_trivia_started(question: String, options: Array, answering_player_idx: int) -> void:
	_submitted_answers.clear()
	_answering_player_idx = answering_player_idx
	_build_overlay(question, options)
	visible = true
	_timer_remaining = Constants.TRIVIA_ANSWER_TIME_SEC
	_timer_active = true
	set_process(true)
	_update_timer_label()

func _build_overlay(question: String, options: Array) -> void:
	if _overlay:
		_overlay.queue_free()

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var status_holder := Control.new()
	status_holder.custom_minimum_size = STATUS_SIZE
	status_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	status_holder.offset_left = -STATUS_SIZE.x * 0.5
	status_holder.offset_top = 44.0
	status_holder.offset_right = STATUS_SIZE.x * 0.5
	status_holder.offset_bottom = 44.0 + STATUS_SIZE.y
	_overlay.add_child(status_holder)

	_status_texture = TextureRect.new()
	_status_texture.texture = TIMER_BG
	_status_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_status_texture.stretch_mode = TextureRect.STRETCH_SCALE
	status_holder.add_child(_status_texture)

	_timer_label = _make_label(36, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	_timer_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_holder.add_child(_timer_label)

	# Score label — shows the answering player's current total score.
	# Displayed below the timer/result box so players can see their running tally.
	var score_holder := Control.new()
	score_holder.custom_minimum_size = Vector2(STATUS_SIZE.x, 36)
	score_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_holder.offset_left = -STATUS_SIZE.x * 0.5
	score_holder.offset_top = 44.0 + STATUS_SIZE.y + 4.0
	score_holder.offset_right = STATUS_SIZE.x * 0.5
	score_holder.offset_bottom = 44.0 + STATUS_SIZE.y + 40.0
	_overlay.add_child(score_holder)

	_score_label = _make_label(22, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	if _answering_player_idx >= 0 and _answering_player_idx < GameManager.players.size():
		var current_score: int = GameManager.players[_answering_player_idx]["score"]
		var player_name: String = GameManager.players[_answering_player_idx]["name"]
		_score_label.text = "%s's Score: %d" % [player_name, current_score]
	_score_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	score_holder.add_child(_score_label)

	var panel_holder := Control.new()
	panel_holder.custom_minimum_size = PANEL_SIZE
	panel_holder.set_anchors_preset(Control.PRESET_CENTER)
	panel_holder.offset_left = -PANEL_SIZE.x * 0.5
	panel_holder.offset_top = -PANEL_SIZE.y * 0.5 + 36.0
	panel_holder.offset_right = PANEL_SIZE.x * 0.5
	panel_holder.offset_bottom = PANEL_SIZE.y * 0.5 + 36.0
	_overlay.add_child(panel_holder)

	var panel_bg := TextureRect.new()
	panel_bg.texture = TRIVIA_BG
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_bg.stretch_mode = TextureRect.STRETCH_SCALE
	panel_holder.add_child(panel_bg)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 30.0
	content.offset_top = 28.0
	content.offset_right = -30.0
	content.offset_bottom = -24.0
	content.add_theme_constant_override("separation", 12)
	panel_holder.add_child(content)

	var question_box := Control.new()
	question_box.custom_minimum_size = QUESTION_SIZE
	content.add_child(question_box)

	var question_bg := TextureRect.new()
	question_bg.texture = QUESTION_BG
	question_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	question_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	question_bg.stretch_mode = TextureRect.STRETCH_SCALE
	question_box.add_child(question_bg)

	var q_label := _make_label(30, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	q_label.text = question
	q_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	q_label.offset_left = 28.0
	q_label.offset_top = 12.0
	q_label.offset_right = -28.0
	q_label.offset_bottom = -12.0
	question_box.add_child(q_label)

	var answers_box := VBoxContainer.new()
	answers_box.add_theme_constant_override("separation", 10)
	content.add_child(answers_box)

	_option_buttons.clear()
	_option_labels.clear()
	_current_selection = 0
	_selected_option = -1
	_has_submitted = false

	for i in options.size():
		var btn := TextureButton.new()
		btn.custom_minimum_size = ANSWER_SIZE
		btn.texture_normal = ANSWER_BGS[i % ANSWER_BGS.size()]
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE
		btn.mouse_entered.connect(_on_option_hovered.bind(i))
		btn.mouse_exited.connect(_on_option_unhovered.bind(i))
		btn.pressed.connect(_on_option_pressed.bind(i))
		answers_box.add_child(btn)
		_option_buttons.append(btn)

		var label := _make_label(27, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
		label.text = "%d. %s" % [i + 1, options[i]]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 22.0
		label.offset_right = -22.0
		btn.add_child(label)
		_option_labels.append(label)

	_update_selector()
	var my_idx: int = NetworkManager.get_my_player_index()
	if my_idx != _answering_player_idx:
		_has_submitted = true
		for i in _option_buttons.size():
			_option_buttons[i].disabled = true
			_option_buttons[i].modulate = Color(1, 1, 1, 0.55)
			_option_labels[i].add_theme_color_override("font_color", DISABLED_TEXT_COLOR)

		var waiting_label := _make_label(24, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
		waiting_label.text = "%s is answering..." % GameManager.players[_answering_player_idx]["name"]
		content.add_child(waiting_label)

func _on_option_hovered(option_idx: int) -> void:
	if _has_submitted:
		return
	_current_selection = option_idx
	_update_selector()

func _on_option_unhovered(option_idx: int) -> void:
	if option_idx >= 0 and option_idx < _option_labels.size() and option_idx != _current_selection:
		_option_labels[option_idx].add_theme_color_override("font_color", TEXT_COLOR)

func _on_option_pressed(option_idx: int) -> void:
	var my_idx: int = NetworkManager.get_my_player_index()
	# In offline/local play there is no ENet peer, so get_my_player_index()
	# returns -1.  Fall back to the current turn's player so answers still work.
	if my_idx == -1:
		my_idx = GameManager.current_player_index
	if _has_submitted:
		return

	_has_submitted = true
	_selected_option = option_idx
	_current_selection = option_idx
	_show_only_selected_option()

	var offline: bool = not multiplayer.has_multiplayer_peer() \
		or multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	if NetworkManager.is_host or offline:
		NetworkManager.process_trivia_answer(my_idx, option_idx)
	else:
		NetworkManager.request_trivia_answer.rpc_id(1, my_idx, option_idx)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _has_submitted or _option_buttons.is_empty():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_W, KEY_UP:
			_current_selection = (_current_selection - 1 + _option_buttons.size()) % _option_buttons.size()
			_update_selector()
		KEY_S, KEY_DOWN:
			_current_selection = (_current_selection + 1) % _option_buttons.size()
			_update_selector()
		KEY_SPACE, KEY_ENTER:
			_on_option_pressed(_current_selection)

func _update_selector() -> void:
	for i in _option_labels.size():
		var color := HOVER_TEXT_COLOR if i == _current_selection else TEXT_COLOR
		_option_labels[i].add_theme_color_override("font_color", color)

func _show_only_selected_option() -> void:
	for i in _option_buttons.size():
		var is_selected := i == _selected_option
		_option_buttons[i].visible = is_selected
		_option_buttons[i].disabled = true
		if is_selected:
			_option_labels[i].add_theme_color_override("font_color", TEXT_COLOR)

func show_results(scores: Dictionary, correct_index: int) -> void:
	_timer_active = false
	set_process(false)

	var answered_correctly := scores.has(_answering_player_idx)
	if _status_texture != null:
		_status_texture.texture = CORRECT_BG if answered_correctly else INCORRECT_BG
	if _timer_label != null:
		_timer_label.text = "CORRECT" if answered_correctly else "WRONG"

	# Show a brief score-change indicator during the reveal window.
	# The score has already been applied to GameManager by the time show_results() runs,
	# so we can read the updated total directly to show the new running score.
	if _score_label != null and _answering_player_idx >= 0 and _answering_player_idx < GameManager.players.size():
		var new_score: int = GameManager.players[_answering_player_idx]["score"]
		if answered_correctly:
			_score_label.text = "+%d point! Score: %d" % [Constants.TRIVIA_POINTS, new_score]
			_score_label.add_theme_color_override("font_color", Color(0.08, 0.55, 0.15))
		else:
			_score_label.text = "Incorrect! Score: %d" % new_score
			_score_label.add_theme_color_override("font_color", Color(0.70, 0.12, 0.10))

	if correct_index >= 0 and correct_index < _option_labels.size():
		_option_labels[correct_index].add_theme_color_override("font_color", Color(0.08, 0.45, 0.12))

	if _selected_option >= 0 and _selected_option < _option_buttons.size():
		_show_only_selected_option()

	await get_tree().create_timer(Constants.TRIVIA_REVEAL_TIME_SEC).timeout
	visible = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null

func _update_timer_label() -> void:
	if _timer_label != null:
		_timer_label.text = str(ceili(_timer_remaining))

func _make_label(font_size: int, h_align: HorizontalAlignment, v_align: VerticalAlignment) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.horizontal_alignment = h_align
	label.vertical_alignment = v_align
	label.clip_text = true
	return label
