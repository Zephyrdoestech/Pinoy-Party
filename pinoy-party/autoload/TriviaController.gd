# autoload/TriviaController.gd
extends CanvasLayer

var _current_question: Dictionary = {}
var _submitted_answers: Dictionary = {}  # player_idx -> option_index
var _overlay: Control
var _option_buttons: Array[Button] = []

func _ready() -> void:
	EventBus.trivia_started.connect(_on_trivia_started)
	layer = 100  # draw above everything
	visible = false

func _on_trivia_started(question: String, options: Array) -> void:
	_submitted_answers.clear()
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

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.add_child(vbox)

	var q_label := Label.new()
	q_label.text = question
	q_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(q_label)

	_option_buttons.clear()
	for i in options.size():
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, options[i]]
		btn.pressed.connect(_on_option_pressed.bind(i))
		vbox.add_child(btn)
		_option_buttons.append(btn)

func _on_option_pressed(option_idx: int) -> void:
	var my_idx: int = NetworkManager.get_my_player_index()
	if my_idx == -1 or _submitted_answers.has(my_idx):
		return
	_submitted_answers[my_idx] = option_idx
	for b in _option_buttons:
		b.disabled = true  # lock in this client's choice, no changing after submit

	if NetworkManager.is_host:
		NetworkManager.process_trivia_answer(my_idx, option_idx)
	else:
		NetworkManager.request_trivia_answer.rpc_id(1, my_idx, option_idx)

func show_results(scores: Dictionary, correct_index: int) -> void:
	# Simple reveal: highlight correct option, show points earned per player.
	if correct_index >= 0 and correct_index < _option_buttons.size():
		_option_buttons[correct_index].modulate = Color.GREEN
	await get_tree().create_timer(Constants.TRIVIA_REVEAL_TIME_SEC).timeout
	visible = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null
