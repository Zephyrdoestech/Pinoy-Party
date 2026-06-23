extends Node2D

@export var player_token_scene: PackedScene = preload("res://scenes/player/PlayerToken.tscn")

@onready var board: Node2D = $Board
@onready var dice: Node2D = $Dice
@onready var roll_button: Button = $UI/RollButton
@onready var turn_label: Label = $UI/TurnLabel
@onready var state_machine: StateMachine = $StateMachine

var tokens: Array[Node2D] = []

func _ready() -> void:
	_spawn_tokens()
	roll_button.pressed.connect(_on_roll_pressed)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.player_moved.connect(_on_player_moved)
	# StateMachine auto-starts itself via call_deferred in its own _ready().
	# No need to call GameManager.start_turn() manually anymore — State_StartTurn does it.

func _spawn_tokens() -> void:
	for i in Constants.MAX_PLAYERS:
		var token: Node2D = player_token_scene.instantiate()
		add_child(token)
		token.setup(i, board)
		token.movement_finished.connect(_on_token_movement_finished)
		tokens.append(token)

func _on_token_movement_finished(player_index: int) -> void:
	EventBus.movement_finished.emit(player_index)

func _on_roll_pressed() -> void:
	# Guard now lives implicitly in State_WaitingForDice — it only listens
	# for dice_rolled while it's the active state, so a stray click while
	# in another state is harmless (dice.roll() just won't have a listener
	# waiting on EventBus.dice_rolled yet).
	dice.roll()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_roll_pressed()

func _on_turn_started(player_index: int) -> void:
	var player_name: String = GameManager.players[player_index]["name"]
	turn_label.text = "%s's turn — roll the dice!" % player_name

func _on_player_moved(player_index: int, new_tile_index: int) -> void:
	# Tell the token to actually animate to its new tile.
	tokens[player_index].move_to(new_tile_index)
