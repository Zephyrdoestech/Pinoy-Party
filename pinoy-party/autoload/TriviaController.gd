# autoload/TriviaController.gd
extends CanvasLayer

var _current_question: Dictionary = {}
var _submitted_answers: Dictionary = {}  # player_idx -> option_index
var _overlay: Control
var _option_buttons: Array[Button] = []
var _option_rows: Array[Label] = []   # the arrow label for each row
var _current_selection: int = 0
var _has_submitted: bool = false
var _answering_player_idx: int = -1


func _ready() -> void:
	EventBus.trivia_started.connect(_on_trivia_started)
	layer = 100  # draw above everything
	visible = false

func _on_trivia_started(question: String, options: Array, answering_player_idx: int) -> void:
	_submitted_answers.clear()
	_answering_player_idx = answering_player_idx
	_build_overlay(question, options)
	visible = true

func _build_overlay(question: String, options: Array) -> void:
	if _overlay:
		_overlay.queue_free()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	# A fixed-width panel centered in the viewport, instead of a bare
	# VBoxContainer with no size constraint — this is what was causing
	# the text to run off the right edge of the window.
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position -= panel.custom_minimum_size / 2.0
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(panel)

	var q_label := Label.new()
	q_label.text = question
	q_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_label.add_theme_font_size_override("font_size", 28)
	panel.add_child(q_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	panel.add_child(spacer)

	_option_rows.clear()
	_option_buttons.clear()
	_current_selection = 0
	_has_submitted = false

	for i in options.size():
		var row := HBoxContainer.new()
		panel.add_child(row)

		var arrow := Label.new()
		arrow.text = "  "
		arrow.custom_minimum_size = Vector2(30, 0)
		row.add_child(arrow)
		_option_rows.append(arrow)

		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, options[i]]
		btn.custom_minimum_size = Vector2(550, 0)
		btn.pressed.connect(_on_option_pressed.bind(i))
		row.add_child(btn)
		_option_buttons.append(btn)

	_update_selector()
	var my_idx: int = NetworkManager.get_my_player_index()
	if my_idx != _answering_player_idx:
		_has_submitted = true  # reuse the existing lock — blocks input and _on_option_pressed
		for b in _option_buttons:
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.5)  # dim to signal "not yours"

		var waiting_label := Label.new()
		waiting_label.text = "%s is answering..." % GameManager.players[_answering_player_idx]["name"]
		waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		waiting_label.add_theme_font_size_override("font_size", 18)
		panel.add_child(waiting_label)

func _on_option_pressed(option_idx: int) -> void:
	var my_idx: int = NetworkManager.get_my_player_index()
	# In offline/local play there is no ENet peer, so get_my_player_index()
	# returns -1.  Fall back to the current turn's player so answers still work.
	if my_idx == -1:
		my_idx = GameManager.current_player_index
	if _has_submitted:
		return
	_has_submitted = true
	_current_selection = option_idx
	_update_selector()
	for b in _option_buttons:
		b.disabled = true  # lock in this client's choice, no changing after submit

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
	for i in _option_rows.size():
		_option_rows[i].text = "▶ " if i == _current_selection else "  "

func show_results(scores: Dictionary, correct_index: int) -> void:
	if correct_index >= 0 and correct_index < _option_buttons.size():
		_option_buttons[correct_index].modulate = Color.GREEN

	var results_label := Label.new()
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.add_theme_font_size_override("font_size", 20)

	var player_name: String = GameManager.players[_answering_player_idx]["name"]
	if scores.has(_answering_player_idx):
		results_label.text = "%s got it right! +%d pt" % [player_name, scores[_answering_player_idx]]
	else:
		results_label.text = "%s did not get it." % player_name

	if _overlay and _overlay.get_child_count() > 1:
		var panel: Control = _overlay.get_child(1)
		panel.add_child(results_label)

	await get_tree().create_timer(Constants.TRIVIA_REVEAL_TIME_SEC).timeout
	visible = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null
