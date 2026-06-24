extends Node2D

@export var player_token_scene: PackedScene = preload("res://scenes/player/PlayerToken.tscn")

@onready var board: Node2D = $Board
@onready var dice: Node2D = $Dice
@onready var roll_button: Button = $UI/RollButton
@onready var turn_label: Label = $UI/TurnLabel
@onready var state_machine: StateMachine = $StateMachine

var tokens: Array[Node2D] = []

# ---------------------------------------------------------------------------
# Board character spritesheets — one per player (0-indexed).
# Path pattern: res://assets/characters/board_characs/charac{N}/charac{N}_walkFront.PNG
# Sheets are 4096×1024px, 4 frames horizontal (hframes=4), imported as
# CompressedTexture2D. player_token.gd slices them into AtlasTexture frames.
# ---------------------------------------------------------------------------
const CHARACTER_SHEETS: Array[String] = [
	"res://assets/characters/board_characs/charac1/charac1_walkFront.PNG",  # Player 1
	"res://assets/characters/board_characs/charac2/charac2_walkFront.PNG",  # Player 2
	"res://assets/characters/board_characs/charac3/charac3_walkFront.PNG",  # Player 3
	"res://assets/characters/board_characs/charac4/charac4_walkFront.PNG",  # Player 4
]

func _ready() -> void:
	_spawn_tokens()
	roll_button.pressed.connect(_on_roll_pressed)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.player_moved.connect(_on_player_moved)
	# StateMachine auto-starts itself via call_deferred in its own _ready().

func _spawn_tokens() -> void:
	for i in Constants.MAX_PLAYERS:
		var token: Node2D = player_token_scene.instantiate()
		add_child(token)

		# Load the spritesheet for this player and pass it into setup().
		# All 4 sheets are confirmed present; load() will assert if a path
		# is wrong, which is the desired loud-failure behaviour during dev.
		var sheet: Texture2D = load(CHARACTER_SHEETS[i])
		token.setup(i, board, sheet)
		token.movement_finished.connect(_on_token_movement_finished)
		tokens.append(token)

func _on_token_movement_finished(player_index: int) -> void:
	EventBus.movement_finished.emit(player_index)

func _on_roll_pressed() -> void:
	# Guard lives in State_WaitingForDice — stray clicks while in another
	# state are harmless (dice.roll() just won't have a listener yet).
	dice.roll()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_roll_pressed()

func _on_turn_started(player_index: int) -> void:
	var player_name: String = GameManager.players[player_index]["name"]
	turn_label.text = "%s's turn — roll the dice!" % player_name

func _on_player_moved(player_index: int, new_tile_index: int) -> void:
	# Tell the token to animate to its new tile.
	tokens[player_index].move_to(new_tile_index)
