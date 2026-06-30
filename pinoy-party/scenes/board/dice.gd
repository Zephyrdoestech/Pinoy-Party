# scenes/board/dice.gd
extends Node2D

@onready var label: Label = $Label

var is_rolling: bool = false

func _ready() -> void:
	EventBus.dice_rolled.connect(_on_dice_rolled)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		roll()

func roll() -> void:
	if is_rolling:
		return
	if NetworkManager.get_my_player_index() != GameManager.current_player_index:
		return  # not your turn
	is_rolling = true

	for i in Constants.DICE_ROLL_TICKS:
		label.text = str(randi_range(1, Constants.DICE_FACES))
		await get_tree().create_timer(0.05).timeout

	# Don't generate the result locally anymore — ask the host for the
	# real roll so every peer ends up with the identical number.
	# If we're the host, call directly — Godot blocks rpc_id(1) on yourself.
	# If we're a client, send the request to the host (peer 1).
	if NetworkManager.is_host:
		NetworkManager._process_roll_request(multiplayer.get_unique_id())
	else:
		NetworkManager.request_roll.rpc_id(1)

# Fires on every peer once the host has broadcast the real roll result
# via EventBus.dice_rolled (emitted from GameManager.on_dice_rolled()).
func _on_dice_rolled(_player_index: int, result: int) -> void:
	label.text = str(result)
	is_rolling = false
