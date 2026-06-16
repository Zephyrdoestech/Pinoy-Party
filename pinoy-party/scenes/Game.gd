extends Node2D

@export var player_token_scene: PackedScene = preload("res://scenes/player/PlayerToken.tscn")

@onready var board: Node2D = $Board
@onready var dice: Node2D = $Dice
@onready var roll_button: Button = $UI/RollButton
@onready var turn_label: Label = $UI/TurnLabel

var tokens: Array[Node2D] = []

func _ready() -> void:
	_spawn_tokens()
	roll_button.pressed.connect(_on_roll_pressed)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.tile_landed.connect(_on_tile_landed)
	GameManager.start_turn()

func _spawn_tokens() -> void:
	for i in Constants.MAX_PLAYERS:
		var token: Node2D = player_token_scene.instantiate()
		add_child(token)
		token.setup(i, board)
		tokens.append(token)

func _on_roll_pressed() -> void:
	# Only allow rolling during the ROLLING state, matches GameManager's state machine.
	if GameManager.state == Enums.GameState.ROLLING:
		dice.roll()

func _on_turn_started(player_index: int) -> void:
	var player_name: String = GameManager.players[player_index]["name"]
	turn_label.text = "%s's turn — roll the dice!" % player_name

func _on_tile_landed(player_index: int, tile_type: int) -> void:
	# TODO: when tile_type == Enums.TileType.GAME_TRIGGER, call SceneLoader.go_to_minigame(Utils.random_minigame())
	# and resolve via GameManager.on_minigame_finished(scores) when that scene returns.
	if tile_type == Enums.TileType.BLANK:
		GameManager.on_minigame_finished({})  # no score change, just advances the turn
